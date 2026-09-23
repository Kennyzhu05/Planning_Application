#include "aiservice.h"
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

AIService::AIService(QObject *parent) : QObject(parent) {
    connect(&m_networkManager, &QNetworkAccessManager::finished, 
            this, &AIService::handleNetworkReply);
}

void AIService::breakdownTask(const QString &prompt, const QString &apiKey) {
    if (apiKey.isEmpty()) {
        emit errorOccurred("API Key is missing. Please provide a valid key.");
        return;
    }

    // Example using OpenAI/Groq compatible chat completions API
    QUrl url("https://api.openai.com/v1/chat/completions");
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("Authorization", QString("Bearer %1").arg(apiKey).toUtf8());

    // Prompt engineering enforcing strict JSON output format
    QJsonObject systemMessage;
    systemMessage["role"] = "system";
    systemMessage["content"] = 
        "You are a productivity AI assistant. Break down high-level user tasks into actionable subtasks. "
        "Return strictly a JSON object with a 'subtasks' array. Each item must contain: "
        "'name' (string), 'category' (string: 'Work', 'Personal', or 'Health'), "
        "and 'minutes' (integer duration estimate between 15 and 120).";

    QJsonObject userMessage;
    userMessage["role"] = "user";
    userMessage["content"] = QString("Break down this task: '%1'").arg(prompt);

    QJsonArray messages;
    messages.append(systemMessage);
    messages.append(userMessage);

    QJsonObject jsonPayload;
    jsonPayload["model"] = "gpt-4o-mini"; // or "llama-3.3-70b-versatile" for Groq
    jsonPayload["messages"] = messages;
    jsonPayload["response_format"] = QJsonObject{{"type", "json_object"}};

    m_networkManager.post(request, QJsonDocument(jsonPayload).toJson());
}

void AIService::handleNetworkReply(QNetworkReply *reply) {
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        emit errorOccurred(reply->errorString());
        return;
    }

    QByteArray responseData = reply->readAll();
    QJsonDocument jsonDoc = QJsonDocument::fromJson(responseData);
    QJsonObject rootObj = jsonDoc.object();

    if (rootObj.contains("choices") && rootObj["choices"].toArray().size() > 0) {
        QString content = rootObj["choices"].toArray()[0].toObject()["message"].toObject()["content"].toString();
        QJsonDocument contentDoc = QJsonDocument::fromJson(content.toUtf8());
        QJsonObject contentObj = contentDoc.object();

        if (contentObj.contains("subtasks")) {
            emit breakdownComplete(contentObj["subtasks"].toArray());
            return;
        }
    }

    emit errorOccurred("Failed to parse structured response from AI.");
}