#pragma once
#include <QString>
#include <QStringList>
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
    QString plannedDate;
    int goalId = 0;
    int goalPosition = 0;
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

struct Goal {
    int id = 0;
    QString name;
    QString description;
    QString successCriteria;
    QString targetDate;
    QString category = "Personal";
    QString startingPoint;
    double weeklyHours = 0;
    bool isCompleted = false;
    QStringList milestones;
};
