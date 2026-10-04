#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QTimer>
#include <QJsonObject>
#include <functional>

class AuthService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool configured READ configured CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool signedIn READ signedIn NOTIFY signedInChanged)
    Q_PROPERTY(QString email READ email NOTIFY signedInChanged)
    Q_PROPERTY(QString message READ message NOTIFY messagesChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY messagesChanged)
    Q_PROPERTY(QString storageMessage READ storageMessage NOTIFY messagesChanged)
public:
    explicit AuthService(QObject *parent = nullptr);
    bool configured() const;
    bool busy() const { return !m_reply.isNull(); }
    bool signedIn() const { return !m_userId.isEmpty() && !m_refreshToken.isEmpty(); }
    QString email() const { return m_email; }
    QString message() const { return m_message; }
    QString errorMessage() const { return m_error; }
    QString storageMessage() const { return m_storageMessage; }
    // Access credentials are intentionally unavailable as QML properties.
    QByteArray accessToken() const { return m_accessToken; }
    QString userId() const { return m_userId; }
    void ensureAccessToken();
    Q_INVOKABLE void signIn(const QString &email, const QString &password);
    Q_INVOKABLE void signUp(const QString &email, const QString &password);
    Q_INVOKABLE void confirmEmail(const QString &email, const QString &code);
    Q_INVOKABLE void resendConfirmation(const QString &email);
    Q_INVOKABLE void sendPasswordReset(const QString &email);
    Q_INVOKABLE void resetPassword(const QString &email, const QString &code, const QString &newPassword);
    Q_INVOKABLE void signOut();
    Q_INVOKABLE void clearMessages();
signals:
    void busyChanged();
    void signedInChanged();
    void messagesChanged();
    void verificationRequired(const QString &email);
    void passwordResetCodeSent(const QString &email);
    void passwordResetComplete();
    void accessTokenReady();
    void accessTokenFailed(const QString &message);
private:
    using Callback = std::function<void(const QJsonObject &, int, const QString &)>;
    void send(const QString &operation, const QString &path, const QJsonObject &body,
              Callback callback, const QByteArray &token = {}, const QByteArray &method = "POST");
    bool begin(const QString &email, const QString &password = {}, bool passwordRequired = false, bool newPassword = false);
    bool validCode(const QString &code);
    bool acceptSession(const QJsonObject &session);
    void refresh();
    void clearSession();
    void fail(const QString &message);
    void inform(const QString &message);
    QString credentialName() const;
    QByteArray readCredential() const;
    bool saveCredential(const QByteArray &value);
    bool removeCredential();
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QTimer m_timeout, m_refreshTimer;
    QUrl m_supabase;
    QByteArray m_publishableKey, m_accessToken, m_refreshToken;
    QString m_userId, m_email, m_message, m_error, m_storageMessage, m_operation;
    qint64 m_expiresAt = 0;
};
