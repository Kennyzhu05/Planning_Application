#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonObject>
#include <QJsonArray>

class AIService : public QObject {
    Q_OBJECT
public:
    explicit AIService(QObject *parent = nullptr);
    
    // Q_INVOKABLE allows QML to trigger this directly
    Q_INVOKABLE void breakdownTask(const QString &prompt, const QString &apiKey);

signals:
    void breakdownComplete(const QJsonArray &subtasks);
    void errorOccurred(const QString &errorMessage);

private slots:
    void handleNetworkReply(QNetworkReply *reply);

private:
    QNetworkAccessManager m_networkManager;
};