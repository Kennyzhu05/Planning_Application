#include "taskmanager.h"
#include "breakdownvalidation.h"
#include <QJsonDocument>
#include <QSqlQuery>
#include <algorithm>
#include <cmath>

bool TaskManager::validDate(const QString &date, bool allowEmpty) {
    if (date.isEmpty()) return allowEmpty;
    const QDate parsed = QDate::fromString(date, Qt::ISODate);
    return parsed.isValid() && parsed.toString(Qt::ISODate) == date && date.size() == 10;
}

void TaskManager::publishChange() {
    ++m_revision;
    emit plannerChanged();
}

void TaskManager::refreshToday() {
    if (m_today == QDate::currentDate()) return;
    m_today = QDate::currentDate();
    recalculatePlannedHours();
    publishChange();
}

int TaskManager::findGoal(int goalId) const {
    for (int i = 0; i < m_goals.size(); ++i) if (m_goals[i].id == goalId) return i;
    return -1;
}

QVariantMap TaskManager::getGoal(int goalId) const {
    const int row = findGoal(goalId);
    if (row < 0) return {};
    const auto &goal = m_goals[row];
    int count = 0, completed = 0;
    for (const auto &task : m_tasks) if (task.goalId == goalId) {
        ++count;
        if (task.isCompleted) ++completed;
    }
    return {{"goalId", goal.id}, {"name", goal.name}, {"description", goal.description},
        {"successCriteria", goal.successCriteria}, {"targetDate", goal.targetDate},
        {"category", goal.category}, {"startingPoint", goal.startingPoint},
        {"weeklyHours", goal.weeklyHours}, {"isCompleted", goal.isCompleted},
        {"milestones", goal.milestones}, {"taskCount", count}, {"completedTaskCount", completed}};
}

QVariantList TaskManager::getGoals() const {
    QVariantList result;
    for (const auto &goal : m_goals) result.append(getGoal(goal.id));
    return result;
}

QVariantList TaskManager::tasksForDate(const QString &date) const {
    QVariantList result;
    if (!validDate(date, false)) return result;
    for (const auto &task : m_tasks)
        if (task.plannedDate == date) result.append(getTask(task.id));
    return result;
}

QVariantList TaskManager::goalsForDate(const QString &date) const {
    QVariantList result;
    if (!validDate(date, false)) return result;
    for (const auto &goal : m_goals)
        if (goal.targetDate == date) result.append(getGoal(goal.id));
    return result;
}

bool TaskManager::hasItemsOnDate(const QString &date) const {
    if (!validDate(date, false)) return false;
    for (const auto &task : m_tasks) if (task.plannedDate == date) return true;
    for (const auto &goal : m_goals) if (goal.targetDate == date) return true;
    return false;
}

QVariantList TaskManager::getGoalTasks(int goalId) const {
    QVector<Task> ordered;
    for (const auto &task : m_tasks) if (task.goalId == goalId) ordered.append(task);
    std::sort(ordered.begin(), ordered.end(), [](const Task &a, const Task &b) {
        return a.goalPosition < b.goalPosition;
    });
    QVariantList result;
    for (const auto &task : ordered) result.append(getTask(task.id));
    return result;
}

bool TaskManager::setTaskDate(int taskId, const QString &plannedDate) {
    const int row = findRow(taskId);
    if (row < 0) return fail("This task no longer exists.");
    if (!validDate(plannedDate)) return fail("Choose a valid planned date.");
    if (plannedDate.isEmpty() && m_tasks[row].goalId == 0)
        return fail("Daily tasks need a planned date.");
    QSqlQuery query(m_db);
    query.prepare("UPDATE tasks SET planned_date = ? WHERE id = ?");
    query.addBindValue(plannedDate.isEmpty() ? QVariant(QString()) : QVariant(plannedDate));
    query.addBindValue(taskId);
    if (!query.exec()) return fail("Could not save the planned date. Please try again.");
    m_tasks[row].plannedDate = plannedDate;
    notifyTask(row);
    return true;
}

bool TaskManager::updateTask(int taskId, const QVariantMap &details) {
    const int row = findRow(taskId);
    if (row < 0) return fail("This task no longer exists.");
    const QString name = details.value("name").toString().trimmed();
    const QString description = details.value("description").toString().trimmed();
    const QString category = details.value("category").toString();
    const QString date = details.value("plannedDate").toString();
    const int minutes = details.value("minutes").toInt();
    if (name.isEmpty() || minutes < 1 || (category != "Work" && category != "Health" && category != "Personal"))
        return fail("Enter a task title, positive duration, and valid category.");
    if (!validDate(date, m_tasks[row].goalId > 0)) return fail("Choose a valid planned date.");
    QSqlQuery query(m_db);
    query.prepare("UPDATE tasks SET name = ?, description = ?, category = ?, minutes = ?, planned_date = ? WHERE id = ?");
    query.addBindValue(name);
    query.addBindValue(description);
    query.addBindValue(category);
    query.addBindValue(minutes);
    query.addBindValue(date.isEmpty() ? QVariant(QString()) : QVariant(date));
    query.addBindValue(taskId);
    if (!query.exec()) return fail("Could not update the task. Please try again.");
    auto &task = m_tasks[row];
    task.name = name;
    task.description = description;
    task.category = category;
    task.estimatedMinutes = minutes;
    task.plannedDate = date;
    notifyTask(row);
    return true;
}

int TaskManager::saveGoal(const QVariantMap &details, int goalId) {
    Goal goal;
    const int row = findGoal(goalId);
    if (goalId > 0 && row < 0) { fail("This goal no longer exists."); return 0; }
    if (row >= 0) goal = m_goals[row];
    goal.name = details.value("name").toString().trimmed();
    goal.description = details.value("description").toString().trimmed();
    goal.successCriteria = details.value("successCriteria").toString().trimmed();
    goal.targetDate = details.value("targetDate").toString();
    goal.category = details.value("category", "Personal").toString();
    goal.startingPoint = details.value("startingPoint").toString().trimmed();
    goal.weeklyHours = details.value("weeklyHours").toDouble();
    if (goal.name.isEmpty() || !validDate(goal.targetDate)
        || !std::isfinite(goal.weeklyHours) || goal.weeklyHours < 0 || goal.weeklyHours > 168
        || (goal.category != "Work" && goal.category != "Health" && goal.category != "Personal")) {
        fail("Enter a goal title, valid target date, category, and weekly availability.");
        return 0;
    }
    QSqlQuery query(m_db);
    query.prepare(row < 0
        ? "INSERT INTO goals (name, description, success_criteria, target_date, category, starting_point, weekly_hours) VALUES (?, ?, ?, ?, ?, ?, ?)"
        : "UPDATE goals SET name = ?, description = ?, success_criteria = ?, target_date = ?, category = ?, starting_point = ?, weekly_hours = ? WHERE id = ?");
    query.addBindValue(goal.name);
    query.addBindValue(goal.description.isNull() ? QStringLiteral("") : goal.description);
    query.addBindValue(goal.successCriteria.isNull() ? QStringLiteral("") : goal.successCriteria);
    query.addBindValue(goal.targetDate.isEmpty() ? QVariant(QString()) : QVariant(goal.targetDate));
    query.addBindValue(goal.category);
    query.addBindValue(goal.startingPoint.isNull() ? QStringLiteral("") : goal.startingPoint);
    query.addBindValue(goal.weeklyHours);
    if (row >= 0) query.addBindValue(goalId);
    if (!query.exec()) { fail("Could not save the goal. Please try again."); return 0; }
    if (row < 0) {
        goal.id = query.lastInsertId().toInt();
        m_goals.append(goal);
    } else m_goals[row] = goal;
    if (!m_tasks.isEmpty()) emit dataChanged(index(0), index(m_tasks.size() - 1), {GoalNameRole});
    publishChange();
    emit goalChanged(goal.id);
    return goal.id;
}

bool TaskManager::toggleGoal(int goalId) {
    const int row = findGoal(goalId);
    if (row < 0) return fail("This goal no longer exists.");
    QSqlQuery query(m_db);
    query.prepare("UPDATE goals SET completed = ? WHERE id = ?");
    query.addBindValue(m_goals[row].isCompleted ? 0 : 1);
    query.addBindValue(goalId);
    if (!query.exec()) return fail("Could not update the goal. Please try again.");
    m_goals[row].isCompleted = !m_goals[row].isCompleted;
    publishChange();
    emit goalChanged(goalId);
    return true;
}

bool TaskManager::saveGoalBreakdown(int goalId, const QVariantList &milestones, const QVariantList &steps) {
    const int goalRow = findGoal(goalId);
    if (goalRow < 0) return fail("This goal no longer exists.");
    QString error;
    if (!validateBreakdown(QJsonArray::fromVariantList(steps), &error)) return fail(error);
    QStringList labels;
    if (milestones.isEmpty() || milestones.size() > 8) return fail("Keep between 1 and 8 milestones.");
    for (const auto &milestone : QJsonArray::fromVariantList(milestones)) {
        if (!milestone.isString() || milestone.toString().trimmed().isEmpty()) return fail("Every milestone needs a title.");
        labels.append(milestone.toString().trimmed());
    }
    for (const auto &step : steps)
        if (!validDate(step.toMap().value("plannedDate").toString())) return fail("Choose valid dates for the suggested tasks.");
    if (!m_db.transaction()) return fail("Could not start saving the goal breakdown.");
    auto rollback = [this]() {
        m_db.rollback();
        return fail("Could not save the goal breakdown. Existing tasks and progress are unchanged.");
    };
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM subtasks WHERE parent_task_id IN (SELECT id FROM tasks WHERE goal_id = ?)");
    query.addBindValue(goalId);
    if (!query.exec()) return rollback();
    query.prepare("DELETE FROM tasks WHERE goal_id = ?");
    query.addBindValue(goalId);
    if (!query.exec()) return rollback();
    QVector<Task> accepted;
    for (int i = 0; i < steps.size(); ++i) {
        const auto step = steps[i].toMap();
        Task task;
        task.name = step.value("name").toString().trimmed();
        task.description = step.value("description").toString().trimmed();
        task.estimatedMinutes = step.value("minutes").toInt();
        task.plannedDate = step.value("plannedDate").toString();
        task.category = m_goals[goalRow].category;
        task.goalId = goalId;
        task.goalPosition = i;
        query.prepare("INSERT INTO tasks (name, description, category, minutes, completed, planned_date, goal_id, goal_position) VALUES (?, ?, ?, ?, 0, ?, ?, ?)");
        query.addBindValue(task.name);
        query.addBindValue(task.description);
        query.addBindValue(task.category);
        query.addBindValue(task.estimatedMinutes);
        query.addBindValue(task.plannedDate.isEmpty() ? QVariant(QString()) : QVariant(task.plannedDate));
        query.addBindValue(goalId);
        query.addBindValue(i);
        if (!query.exec()) return rollback();
        task.id = query.lastInsertId().toInt();
        accepted.append(task);
    }
    query.prepare("UPDATE goals SET milestones = ? WHERE id = ?");
    query.addBindValue(QString::fromUtf8(QJsonDocument(QJsonArray::fromStringList(labels)).toJson(QJsonDocument::Compact)));
    query.addBindValue(goalId);
    if (!query.exec() || !m_db.commit()) return rollback();
    QVector<int> removed;
    beginResetModel();
    for (int i = m_tasks.size() - 1; i >= 0; --i) if (m_tasks[i].goalId == goalId) {
        removed.append(m_tasks[i].id);
        m_tasks.removeAt(i);
    }
    m_tasks += accepted;
    m_goals[goalRow].milestones = labels;
    endResetModel();
    recalculatePlannedHours();
    for (int id : removed) emit taskRemoved(id);
    publishChange();
    emit goalChanged(goalId);
    return true;
}
