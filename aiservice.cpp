#include "aiservice.h"
#include "authservice.h"
#include "dailyplannerconfig.h"
#include "breakdownvalidation.h"
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QDate>
#include <QUuid>
#include <memory>

namespace {
bool allowedEndpoint(const QUrl &url) {
    if (!url.isValid() || url.host().isEmpty() || !url.userInfo().isEmpty()
        || !url.query().isEmpty() || !url.fragment().isEmpty()) return false;
    if (url.scheme() == "https") return true;
    return qEnvironmentVariable("DAILYPLANNER_ALLOW_LOCAL_HTTP") == "1" && url.scheme() == "http"
        && (url.host() == "127.0.0.1" || url.host() == "localhost" || url.host() == "::1");
}
}

AIService::AIService(QObject *parent, const QUrl &endpoint, int timeoutMs)
    : QObject(parent), m_endpoint(endpoint) {
    if (m_endpoint.isEmpty()) {
        QString configured = qEnvironmentVariable("DAILYPLANNER_API_URL").trimmed();
        if (configured.isEmpty()) configured = QString::fromUtf8(DAILYPLANNER_API_URL);
        m_endpoint = QUrl(configured);
    }
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(timeoutMs);
    connect(&m_timeout, &QTimer::timeout, this, [this]() {
        const int entityId = m_taskId;
        const QString kind = m_kind;
        cancel();
        reportError(kind, entityId, "The AI request timed out. Please try again.");
    });
}

void AIService::setAuthService(AuthService *auth) {
    cancel();
    if (m_auth) disconnect(m_auth, nullptr, this, nullptr);
    m_auth = auth;
    if (!auth) return;
    connect(auth, &AuthService::accessTokenReady, this, &AIService::postPendingRequest);
    connect(auth, &AuthService::accessTokenFailed, this, [this](const QString &message) {
        if (!m_pending) return;
        const QString kind = m_kind;
        const int entityId = m_taskId;
        cancel();
        reportError(kind, entityId, message);
        if (m_auth && !m_auth->signedIn()) emit authenticationRequired();
    });
    connect(auth, &AuthService::signedInChanged, this, [this]() {
        if (!busy() || (m_auth && m_auth->signedIn() && m_auth->userId() == m_requestUserId)) return;
        const QString kind = m_kind;
        const int entityId = m_taskId;
        cancel();
        reportError(kind, entityId, "The signed-in account changed. Please try AI breakdown again.");
    });
}

void AIService::cancel() {
    m_timeout.stop();
    const bool wasBusy = busy();
    auto reply = m_reply.data();
    m_reply.clear();
    m_pending = false;
    m_context.clear();
    m_requestId.clear();
    m_requestUserId.clear();
    m_taskId = -1;
    m_kind.clear();
    if (reply) { reply->abort(); reply->deleteLater(); }
    if (wasBusy) emit busyChanged();
}
void AIService::reportError(const QString &kind, int entityId, const QString &message) {
    if (kind == "goal") emit goalErrorOccurred(entityId, message);
    else emit errorOccurred(entityId, message);
}
void AIService::breakdownTask(int taskId, const QVariantMap &task) {
    if (busy()) return;
    if (taskId <= 0 || task.value("taskId").toInt() != taskId || task.value("name").toString().trimmed().isEmpty()) {
        reportError("task", taskId, "This task is unavailable. Close the card and try again."); return;
    }
    startRequest("task", taskId, task);
}
void AIService::breakdownGoal(int goalId, const QVariantMap &goal) {
    if (busy()) return;
    if (goalId <= 0 || goal.value("goalId").toInt() != goalId || goal.value("name").toString().trimmed().isEmpty()) {
        reportError("goal", goalId, "This goal is unavailable. Close the card and try again."); return;
    }
    startRequest("goal", goalId, goal);
}
void AIService::startRequest(const QString &kind, int entityId, const QVariantMap &task) {
    if (!allowedEndpoint(m_endpoint)) {
        reportError(kind, entityId, "AI is not configured. Set DAILYPLANNER_API_URL to your HTTPS backend's /v1/breakdown address."); return;
    }
    if (!m_auth || !m_auth->signedIn()) {
        reportError(kind, entityId, "Sign in to use AI breakdown. Your tasks remain saved on this device.");
        emit authenticationRequired(); return;
    }
    m_kind = kind;
    m_taskId = entityId;
    m_context = task;
    m_requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_requestUserId = m_auth->userId();
    m_pending = true;
    m_timeout.start();
    emit busyChanged();
    m_auth->ensureAccessToken();
}
void AIService::postPendingRequest() {
    if (!m_pending || !m_auth || !m_auth->signedIn()) return;
    const bool goal = m_kind == "goal";
    QJsonObject context{{"title", m_context.value("name").toString()},
        {"description", m_context.value("description").toString()},
        {"category", m_context.value("category").toString()}};
    if (goal) {
        context.insert("successCriteria", m_context.value("successCriteria").toString());
        context.insert("startingPoint", m_context.value("startingPoint").toString());
        context.insert("targetDate", m_context.value("targetDate").toString());
        context.insert("weeklyHours", m_context.value("weeklyHours").toDouble());
        context.insert("today", QDate::currentDate().toString(Qt::ISODate));
    } else context.insert("estimatedMinutes", m_context.value("minutes").toInt());
    const QJsonObject payload{{"kind", m_kind}, {"requestId", m_requestId}, {"context", context}};
    QNetworkRequest request(m_endpoint);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("Authorization", "Bearer " + m_auth->accessToken());
    auto reply = m_networkManager.post(request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    reply->setReadBufferSize(65537);
    m_reply = reply;
    m_pending = false;
    m_context.clear();
    const auto buffer = std::make_shared<QByteArray>();
    connect(reply, &QNetworkReply::readyRead, this, [this, reply, buffer]() {
        if (m_reply != reply) return;
        buffer->append(reply->readAll());
        if (buffer->size() > 65536) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, buffer, entityId = m_taskId]() {
        if (m_reply != reply) { reply->deleteLater(); return; }
        buffer->append(reply->readAll());
        reply->setProperty("backendBody", *buffer);
        finish(reply, entityId);
    });
}
void AIService::finish(QNetworkReply *reply, int entityId) {
    if (m_reply != reply) { reply->deleteLater(); return; }
    m_timeout.stop();
    const QString kind = m_kind, requestId = m_requestId;
    const bool goal = kind == "goal";
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray body = reply->property("backendBody").toByteArray();
    const auto networkError = reply->error();
    const QByteArray retryAfter = reply->rawHeader("Retry-After");
    m_reply.clear(); m_taskId = -1; m_kind.clear(); m_requestId.clear(); m_requestUserId.clear();
    reply->deleteLater();
    emit busyChanged();

    QJsonParseError parse;
    const auto document = QJsonDocument::fromJson(body, &parse);
    const auto response = document.object();
    QString error;
    if (body.size() > 65536) error = "The AI backend returned an oversized response. Please try again later.";
    else if (status >= 400) {
        const auto detail = response.value("error").toObject();
        const QString message = detail.value("message").toString();
        if (parse.error == QJsonParseError::NoError && !message.isEmpty() && message.size() <= 500) error = message;
        else if (status == 401) error = "Your session expired. Sign in again.";
        else if (status == 403) error = "This account is not enabled for AI. Ask the project owner to enable it.";
        else if (status == 429) error = "An AI usage limit was reached. Wait and try again.";
        else if (status == 504) error = "The AI request timed out. Please try again.";
        else if (status >= 500) error = "The AI backend is temporarily unavailable. Please try again later.";
        else error = "The AI backend could not process this task. Check its details and try again.";
        bool valid = false;
        const qint64 seconds = retryAfter.toLongLong(&valid);
        if (status == 429 && valid && seconds > 0) error += QString(" Retry in %1 seconds.").arg(seconds);
    } else if (status >= 300) error = "The backend address redirected. Configure its final HTTPS /v1/breakdown address.";
    else if (networkError != QNetworkReply::NoError) error = "Could not connect to the AI backend. Check your internet connection and try again.";
    if (!error.isEmpty()) {
        reportError(kind, entityId, error);
        if (status == 401) emit authenticationRequired();
        return;
    }
    if (parse.error != QJsonParseError::NoError || !document.isObject()
        || response.value("kind").toString() != kind || response.value("requestId").toString() != requestId
        || !response.value(goal ? "tasks" : "subtasks").isArray()) {
        reportError(kind, entityId, "The AI backend returned an invalid response. Please try again."); return;
    }
    const auto steps = response.value(goal ? "tasks" : "subtasks").toArray();
    if (!validateBreakdown(steps, &error)) { reportError(kind, entityId, "The AI returned an invalid breakdown. " + error); return; }
    for (const auto &step : steps) {
        const auto item = step.toObject();
        if (item.value("name").toString().size() > 200 || item.value("description").toString().trimmed().isEmpty()
            || item.value("description").toString().size() > 1500) {
            reportError(kind, entityId, "The AI returned invalid step guidance. Please try again."); return;
        }
    }
    if (goal) {
        const auto milestones = response.value("milestones").toArray();
        if (milestones.isEmpty() || milestones.size() > 8) { reportError(kind, entityId, "The AI returned an invalid milestone list."); return; }
        for (const auto &milestone : milestones) {
            if (!milestone.isString() || milestone.toString().trimmed().isEmpty() || milestone.toString().size() > 200) {
                reportError(kind, entityId, "The AI returned an invalid milestone. Please try again."); return;
            }
        }
        emit goalBreakdownComplete(entityId, milestones.toVariantList(), steps.toVariantList());
    } else emit breakdownComplete(entityId, steps.toVariantList());
}
