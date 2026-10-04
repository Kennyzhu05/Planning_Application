#include "authservice.h"
#include "dailyplannerconfig.h"
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QDateTime>
#include <QCryptographicHash>
#include <QRegularExpression>
#include <cmath>
#include <memory>
#include <string>
#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <wincred.h>
#endif

namespace {
QString publicSetting(const char *environment, const char *fallback) {
    const QString value = qEnvironmentVariable(environment).trimmed();
    return value.isEmpty() ? QString::fromUtf8(fallback) : value;
}
const QRegularExpression emailPattern("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");
const QRegularExpression codePattern("^[0-9]{6,10}$");
}

AuthService::AuthService(QObject *parent) : QObject(parent) {
    m_supabase = QUrl(publicSetting("DAILYPLANNER_SUPABASE_URL", DAILYPLANNER_SUPABASE_URL));
    if (m_supabase.path() == "/") m_supabase.setPath(QString());
    m_publishableKey = publicSetting("DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY", DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY).toUtf8();
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(20000);
    connect(&m_timeout, &QTimer::timeout, this, [this]() { if (m_reply) m_reply->abort(); });
    m_refreshTimer.setSingleShot(true);
    connect(&m_refreshTimer, &QTimer::timeout, this, [this]() {
        if (busy()) { m_refreshTimer.start(5000); return; }
        refresh();
    });
#ifdef Q_OS_WIN
    m_storageMessage = "Sign-in is remembered securely for this Windows user.";
#else
    m_storageMessage = "Sign-in lasts until the app closes on this platform.";
#endif
    QTimer::singleShot(0, this, [this]() {
        if (!configured()) return;
        m_refreshToken = readCredential();
        if (!m_refreshToken.isEmpty()) refresh();
    });
}

bool AuthService::configured() const {
    static const QRegularExpression host("^[a-z0-9-]+\\.supabase\\.co$");
    return m_supabase.isValid() && m_supabase.scheme() == "https"
        && host.match(m_supabase.host()).hasMatch() && m_supabase.port() == -1
        && m_supabase.userInfo().isEmpty() && m_supabase.query().isEmpty() && m_supabase.fragment().isEmpty()
        && (m_supabase.path().isEmpty() || m_supabase.path() == "/")
        // Only the current PUBLIC key format is accepted. Admin/secret keys never belong in the client.
        && m_publishableKey.startsWith("sb_publishable_") && m_publishableKey.size() < 4096
        && !m_publishableKey.contains('\r') && !m_publishableKey.contains('\n');
}
void AuthService::clearMessages() { m_message.clear(); m_error.clear(); emit messagesChanged(); }
void AuthService::fail(const QString &message) { m_error = message; m_message.clear(); emit messagesChanged(); }
void AuthService::inform(const QString &message) { m_message = message; m_error.clear(); emit messagesChanged(); }

bool AuthService::begin(const QString &email, const QString &password, bool passwordRequired, bool newPassword) {
    if (busy()) return false;
    clearMessages();
    if (!configured()) { fail("Sign-in is not configured yet. Follow the backend setup guide; local planning is available."); return false; }
    if (email.trimmed().size() > 254 || !emailPattern.match(email.trimmed()).hasMatch()) {
        fail("Enter a valid email address."); return false;
    }
    if (passwordRequired && (password.isEmpty() || password.size() > 128 || (newPassword && password.size() < 8))) {
        fail(newPassword ? "Choose a password between 8 and 128 characters." : "Enter your password (up to 128 characters).");
        return false;
    }
    return true;
}
bool AuthService::validCode(const QString &code) {
    if (codePattern.match(code.trimmed()).hasMatch()) return true;
    fail("Enter the verification code from your email."); return false;
}

void AuthService::send(const QString &operation, const QString &path, const QJsonObject &body,
                       Callback callback, const QByteArray &token, const QByteArray &method) {
    if (busy()) return;
    QUrl endpoint = m_supabase;
    endpoint.setPath("/auth/v1/" + path.section('?', 0, 0));
    endpoint.setQuery(path.contains('?') ? path.section('?', 1) : QString());
    QNetworkRequest request(endpoint);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("apikey", m_publishableKey);
    if (!token.isEmpty()) request.setRawHeader("Authorization", "Bearer " + token);
    auto reply = m_network.sendCustomRequest(request, method, QJsonDocument(body).toJson(QJsonDocument::Compact));
    reply->setReadBufferSize(65537);
    m_reply = reply;
    m_operation = operation;
    const auto buffer = std::make_shared<QByteArray>();
    connect(reply, &QNetworkReply::readyRead, this, [this, reply, buffer]() {
        if (m_reply != reply) return;
        buffer->append(reply->readAll());
        if (buffer->size() > 65536) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, buffer, callback = std::move(callback)]() {
        if (m_reply != reply) { reply->deleteLater(); return; }
        m_timeout.stop();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        buffer->append(reply->readAll());
        const auto networkError = reply->error();
        reply->deleteLater();
        m_reply.clear();
        m_operation.clear();
        emit busyChanged();
        QJsonParseError parse;
        const auto document = QJsonDocument::fromJson(*buffer, &parse);
        QString error;
        if (buffer->size() > 65536) error = "The account service returned an invalid response.";
        else if (status == 429) error = "Too many account requests. Wait a little, then try again.";
        else if (status >= 500) error = "The account service is temporarily unavailable. Try again later.";
        else if (status >= 300) {
            const QString code = document.object().value("error_code").toString();
            if (code == "invalid_credentials") error = "The email or password is incorrect.";
            else if (code == "email_not_confirmed") error = "Verify your email first. Use the email verification option below.";
            else if (code == "otp_expired") error = "That email code expired or is invalid. Request a new code.";
            else if (code == "weak_password") error = "Choose a stronger password that meets the account service's rules.";
            else if (code == "same_password") error = "Choose a different password from the current one.";
            else if (code == "email_address_not_authorized") error = "Email delivery is not configured for this address. Ask the project owner to configure SMTP.";
            else error = "The account request could not be completed. Check your details and try again.";
        } else if (networkError == QNetworkReply::OperationCanceledError) error = "The account request timed out. Please try again.";
        else if (networkError != QNetworkReply::NoError) error = "Could not connect to the account service. Check your internet connection.";
        else if (!buffer->isEmpty() && (parse.error != QJsonParseError::NoError || !document.isObject()))
            error = "The account service returned an invalid response.";
        callback(document.object(), status, error);
    });
    m_timeout.start();
    emit busyChanged();
}

bool AuthService::acceptSession(const QJsonObject &session) {
    const auto access = session.value("access_token").toString().toUtf8();
    const auto refreshToken = session.value("refresh_token").toString().toUtf8();
    const auto user = session.value("user").toObject();
    const auto id = user.value("id").toString();
    const auto email = user.value("email").toString();
    const double lifetime = session.value("expires_in").toDouble();
    if (access.isEmpty() || access.size() > 8192 || access.contains('\r') || access.contains('\n')
        || refreshToken.isEmpty() || refreshToken.size() > 2048 || id.isEmpty() || email.isEmpty()
        || !std::isfinite(lifetime) || lifetime < 60 || lifetime > 86400) {
        fail("The account service returned an invalid session. Sign in again."); return false;
    }
    m_accessToken = access;
    m_refreshToken = refreshToken;
    m_userId = id;
    m_email = email;
    m_expiresAt = QDateTime::currentSecsSinceEpoch() + static_cast<qint64>(lifetime);
    if (!saveCredential(m_refreshToken)) {
        removeCredential();
#ifdef Q_OS_WIN
        m_storageMessage = "This sign-in could not be saved securely and lasts until the app closes.";
#endif
    }
    m_refreshTimer.start(static_cast<int>(qMax<qint64>(5000, (static_cast<qint64>(lifetime) - 60) * 1000)));
    emit signedInChanged();
    emit messagesChanged();
    return true;
}

void AuthService::signIn(const QString &email, const QString &password) {
    if (!begin(email, password, true)) return;
    send("login", "token?grant_type=password", {{"email", email.trimmed()}, {"password", password}},
         [this](const QJsonObject &response, int, const QString &error) {
        if (!error.isEmpty()) { fail(error); return; }
        if (acceptSession(response)) inform("You are signed in. AI breakdown is ready when your account is enabled.");
    });
}
void AuthService::signUp(const QString &email, const QString &password) {
    if (!begin(email, password, true, true)) return;
    send("signup", "signup", {{"email", email.trimmed()}, {"password", password}},
         [this, email = email.trimmed()](const QJsonObject &response, int, const QString &error) {
        if (!error.isEmpty()) { fail(error); return; }
        if (response.contains("access_token")) {
            if (acceptSession(response)) inform("Your account is ready.");
        } else {
            inform("Check your email for a verification code. If you already have an account, sign in instead.");
            emit verificationRequired(email);
        }
    });
}
void AuthService::confirmEmail(const QString &email, const QString &code) {
    if (!begin(email) || !validCode(code)) return;
    send("confirm", "verify", {{"email", email.trimmed()}, {"token", code.trimmed()}, {"type", "signup"}},
         [this](const QJsonObject &response, int, const QString &error) {
        if (!error.isEmpty()) { fail(error); return; }
        if (acceptSession(response)) inform("Email verified. You are signed in.");
    });
}
void AuthService::resendConfirmation(const QString &email) {
    if (!begin(email)) return;
    send("resend", "resend", {{"email", email.trimmed()}, {"type", "signup"}},
         [this, email = email.trimmed()](const QJsonObject &, int, const QString &error) {
        if (!error.isEmpty()) { fail(error); return; }
        inform("If this account needs verification, a new code has been sent.");
        emit verificationRequired(email);
    });
}
void AuthService::sendPasswordReset(const QString &email) {
    if (!begin(email)) return;
    send("recover", "recover", {{"email", email.trimmed()}},
         [this, email = email.trimmed()](const QJsonObject &, int, const QString &error) {
        if (!error.isEmpty()) { fail(error); return; }
        inform("If this email has an account, a password reset code has been sent.");
        emit passwordResetCodeSent(email);
    });
}
void AuthService::resetPassword(const QString &email, const QString &code, const QString &newPassword) {
    if (!begin(email, newPassword, true, true) || !validCode(code)) return;
    send("verify-recovery", "verify", {{"email", email.trimmed()}, {"token", code.trimmed()}, {"type", "recovery"}},
         [this, newPassword](const QJsonObject &response, int, const QString &error) {
        if (!error.isEmpty()) { fail(error); return; }
        const QByteArray token = response.value("access_token").toString().toUtf8();
        if (token.isEmpty() || token.size() > 8192 || token.contains('\r') || token.contains('\n')) {
            fail("The reset code could not be verified. Request a new code."); return;
        }
        // Recovery credentials remain temporary and never become the planner's login session.
        send("update-password", "user", {{"password", newPassword}},
             [this](const QJsonObject &, int, const QString &error) {
            if (!error.isEmpty()) { fail(error + " Request a new reset code before trying again."); return; }
            clearSession();
            inform("Password changed. Sign in with your new password.");
            emit passwordResetComplete();
        }, token, "PUT");
    });
}

void AuthService::ensureAccessToken() {
    if (busy() && m_operation == "refresh") return; // Existing refresh emits ready/failed.
    if (!signedIn()) { emit accessTokenFailed("Sign in to use AI breakdown."); return; }
    if (busy()) { emit accessTokenFailed("Finish the account request, then try AI breakdown again."); return; }
    if (m_expiresAt > QDateTime::currentSecsSinceEpoch() + 45) emit accessTokenReady();
    else refresh();
}
void AuthService::refresh() {
    if (busy() || m_refreshToken.isEmpty()) return;
    send("refresh", "token?grant_type=refresh_token", {{"refresh_token", QString::fromUtf8(m_refreshToken)}},
         [this](const QJsonObject &response, int status, const QString &error) {
        if (!error.isEmpty()) {
            // Transient failures preserve the refresh credential for manual retry.
            if (status == 400 || status == 401 || status == 403) {
                clearSession(); fail("Your session expired. Sign in again.");
            } else { fail(error); if (!m_refreshToken.isEmpty()) m_refreshTimer.start(30000); }
            emit accessTokenFailed(m_error); return;
        }
        if (!acceptSession(response)) { clearSession(); emit accessTokenFailed(m_error); return; }
        emit accessTokenReady();
    });
}
void AuthService::clearSession() {
    m_refreshTimer.stop();
    m_accessToken.clear(); m_refreshToken.clear(); m_userId.clear(); m_email.clear(); m_expiresAt = 0;
    if (!removeCredential()) {
        m_storageMessage = "Windows could not remove the saved sign-in. Remove DailyPlanner from Credential Manager.";
        fail(m_storageMessage);
    }
    emit signedInChanged(); emit messagesChanged();
}
void AuthService::signOut() {
    clearMessages();
    const QByteArray token = m_accessToken;
    if (m_reply) {
        auto reply = m_reply.data(); m_reply.clear(); reply->abort(); reply->deleteLater();
        m_timeout.stop(); m_operation.clear(); emit busyChanged();
    }
    clearSession();
    emit accessTokenFailed("You signed out. Sign in again to use AI breakdown.");
    if (m_error.isEmpty()) inform("Signed out on this device.");
    if (!token.isEmpty() && configured()) send("logout", "logout?scope=local", {},
        [this](const QJsonObject &, int, const QString &error) {
            if (!error.isEmpty() && m_error.isEmpty()) inform("Signed out locally. The server session could not be revoked; it will expire normally.");
        }, token);
}

QString AuthService::credentialName() const {
    return "DailyPlanner/Supabase/" + QString::fromLatin1(QCryptographicHash::hash(m_supabase.toEncoded(), QCryptographicHash::Sha256).toHex());
}
QByteArray AuthService::readCredential() const {
#ifdef Q_OS_WIN
    PCREDENTIALW credential = nullptr;
    const std::wstring target = credentialName().toStdWString();
    if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &credential)) return {};
    QByteArray result(reinterpret_cast<const char *>(credential->CredentialBlob), static_cast<int>(credential->CredentialBlobSize));
    CredFree(credential);
    return result.size() <= 2048 ? result : QByteArray();
#else
    return {};
#endif
}
bool AuthService::saveCredential(const QByteArray &value) {
#ifdef Q_OS_WIN
    const std::wstring target = credentialName().toStdWString();
    CREDENTIALW credential{};
    credential.Type = CRED_TYPE_GENERIC;
    credential.TargetName = const_cast<LPWSTR>(target.c_str());
    credential.CredentialBlobSize = static_cast<DWORD>(value.size());
    credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char *>(value.constData()));
    credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
    return CredWriteW(&credential, 0);
#else
    Q_UNUSED(value);
    return false;
#endif
}
bool AuthService::removeCredential() {
#ifdef Q_OS_WIN
    const std::wstring target = credentialName().toStdWString();
    return CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) || GetLastError() == ERROR_NOT_FOUND;
#else
    return true;
#endif
}
