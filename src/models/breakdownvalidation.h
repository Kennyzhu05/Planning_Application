#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <cmath>

// Shared by API parsing and saving the editable preview.
inline bool validateBreakdown(const QJsonArray &steps, QString *error) {
    if (steps.isEmpty() || steps.size() > 12) {
        *error = "A breakdown must contain between 1 and 12 steps.";
        return false;
    }
    for (const auto &value : steps) {
        const auto step = value.toObject();
        const auto minutes = step.value("minutes");
        if (!value.isObject() || !step.value("name").isString()
            || step.value("name").toString().trimmed().isEmpty()
            || !step.value("description").isString()
            || !minutes.isDouble() || minutes.toDouble() != std::floor(minutes.toDouble())
            || minutes.toDouble() < 1 || minutes.toDouble() > 120) {
            *error = "Each step needs a title, guidance, and a whole-number duration from 1 to 120 minutes.";
            return false;
        }
    }
    return true;
}
