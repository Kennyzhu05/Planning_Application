#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>
#include <QPointer>
#include <QVariantMap>
#include <QVariantList>

class AuthService;

class AIService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int activeTaskId READ activeTaskId NOTIFY busyChanged)
    Q_PROPERTY(int activeGoalId READ activeGoalId NOTIFY busyChanged)
public:
    // This endpoint belongs to DailyPlanner's backend, never to the provider.
    explicit AIService(QObject *parent = nullptr,
        const QUrl &endpoint = QUrl(),
        int timeoutMs = 45000);
    void setAuthService(AuthService *auth);
    Q_INVOKABLE void breakdownTask(int taskId, const QVariantMap &task);
    Q_INVOKABLE void breakdownGoal(int goalId, const QVariantMap &goal);
    Q_INVOKABLE void cancel();
    bool busy() const { return m_pending || !m_reply.isNull(); }
    int activeTaskId() const { return m_kind == "task" ? m_taskId : -1; }
    int activeGoalId() const { return m_kind == "goal" ? m_taskId : -1; }
signals:
    void busyChanged();
    void breakdownComplete(int taskId, const QVariantList &subtasks);
    void errorOccurred(int taskId, const QString &message);
    void goalBreakdownComplete(int goalId, const QVariantList &milestones, const QVariantList &tasks);
    void goalErrorOccurred(int goalId, const QString &message);
    void authenticationRequired();
private:
    void startRequest(const QString &kind, int entityId, const QVariantMap &context);
    void postPendingRequest();
    void reportError(const QString &kind, int entityId, const QString &message);
    void finish(QNetworkReply *reply, int taskId);
    QNetworkAccessManager m_networkManager;
    QPointer<QNetworkReply> m_reply;
    QTimer m_timeout;
    QUrl m_endpoint;
    int m_taskId = -1;
    QString m_kind;
    QPointer<AuthService> m_auth;
    QVariantMap m_context;
    QString m_requestId;
    QString m_requestUserId;
    bool m_pending = false;
};
