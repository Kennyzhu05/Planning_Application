#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>
#include <QPointer>
#include <QVariantMap>
#include <QVariantList>

class AIService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int activeTaskId READ activeTaskId NOTIFY busyChanged)
public:
    // Endpoint/timeout injection allows isolated local HTTP tests. The app uses the defaults.
    explicit AIService(QObject *parent = nullptr,
        const QUrl &endpoint = QUrl("https://api.groq.com/openai/v1/chat/completions"),
        int timeoutMs = 45000);
    Q_INVOKABLE void breakdownTask(int taskId, const QVariantMap &task);
    Q_INVOKABLE void cancel();
    bool busy() const { return !m_reply.isNull(); }
    int activeTaskId() const { return m_taskId; }
signals:
    void busyChanged();
    void breakdownComplete(int taskId, const QVariantList &subtasks);
    void errorOccurred(int taskId, const QString &message);
private:
    void finish(QNetworkReply *reply, int taskId);
    QNetworkAccessManager m_networkManager;
    QPointer<QNetworkReply> m_reply;
    QTimer m_timeout;
    QUrl m_endpoint;
    int m_taskId = -1;
};
