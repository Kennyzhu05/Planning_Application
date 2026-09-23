#pragma once
#include <QString>
#include <QObject>

struct Task {
    QString id;
    QString name;
    QString category;
    int estimatedMinutes; // Stored in minutes for precise calculation
    QString description;
    bool isCompleted;
};