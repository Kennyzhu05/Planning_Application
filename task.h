#pragma once
#include <QString>
#include <QVector>

struct Subtask {
    int id = 0;
    QString name;
    QString description;
    int minutes = 0;
    bool isCompleted = false;
};

struct Task {
    int id = 0;
    QString name;
    QString category;
    int estimatedMinutes = 0;
    QString description;
    bool isCompleted = false;
    QVector<Subtask> subtasks;
    int effectiveMinutes() const {
        if (subtasks.isEmpty()) return estimatedMinutes;
        int total = 0;
        for (const auto &step : subtasks) total += step.minutes;
        return total;
    }
    int completedSubtasks() const {
        int count = 0;
        for (const auto &step : subtasks) if (step.isCompleted) ++count;
        return count;
    }
};
