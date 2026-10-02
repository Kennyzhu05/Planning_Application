#include "taskmanager.h"
#include "breakdownvalidation.h"
#include <QJsonArray>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QUuid>
#include <cmath>

TaskManager::TaskManager(QObject *parent, const QString &databasePath) : QAbstractListModel(parent) {
    if (initDatabase(databasePath)) loadTasksFromDb();
}

TaskManager::~TaskManager() {
    const QString connection = m_db.connectionName();
    m_db.close();
    m_db = QSqlDatabase();
    QSqlDatabase::removeDatabase(connection);
}

bool TaskManager::fail(const QString &message) {
    emit errorOccurred(message);
    return false;
}

bool TaskManager::initDatabase(const QString &databasePath) {
    m_db = QSqlDatabase::addDatabase("QSQLITE", QUuid::createUuid().toString());
    m_db.setDatabaseName(databasePath);
    if (!m_db.open()) return fail("Cannot open the planner database.");
    QSqlQuery query(m_db);
    const QStringList schema = {
        "PRAGMA foreign_keys = ON",
        "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)",
        "CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, "
        "category TEXT, minutes INTEGER, description TEXT, completed INTEGER)",
        "CREATE TABLE IF NOT EXISTS subtasks (id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "parent_task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, "
        "position INTEGER NOT NULL, name TEXT NOT NULL, description TEXT NOT NULL, "
        "minutes INTEGER NOT NULL CHECK(minutes BETWEEN 1 AND 120), "
        "completed INTEGER NOT NULL DEFAULT 0, UNIQUE(parent_task_id, position))"
    };
    for (const auto &statement : schema)
        if (!query.exec(statement)) return fail("Cannot initialize the planner database.");

    // Older databases used estimatedMinutes. CREATE TABLE IF NOT EXISTS does
    // not update existing columns, so retain their values by renaming in place.
    const QSqlRecord taskColumns = m_db.record("tasks");
    if (!taskColumns.contains("minutes")) {
        if (!taskColumns.contains("estimatedMinutes"))
            return fail("The planner database is missing its task duration column.");
        if (!query.exec("ALTER TABLE tasks RENAME COLUMN estimatedMinutes TO minutes"))
            return fail("Could not update the planner database. Existing tasks are unchanged.");
    }

    query.exec("SELECT value FROM settings WHERE key = 'targetHours'");
    if (query.next()) m_targetHours = query.value(0).toDouble();
    return true;
}

void TaskManager::loadTasksFromDb() {
    beginResetModel();
    m_tasks.clear();
    QSqlQuery query(m_db);
    query.exec("SELECT id, name, category, minutes, description, completed FROM tasks ORDER BY id");
    while (query.next()) {
        Task task;
        task.id = query.value(0).toInt();
        task.name = query.value(1).toString();
        task.category = query.value(2).toString();
        task.estimatedMinutes = query.value(3).toInt();
        task.description = query.value(4).toString();
        task.isCompleted = query.value(5).toBool();
        m_tasks.append(task);
    }
    query.exec("SELECT id, parent_task_id, name, description, minutes, completed "
               "FROM subtasks ORDER BY parent_task_id, position");
    while (query.next()) {
        int row = findRow(query.value(1).toInt());
        if (row >= 0) m_tasks[row].subtasks.append({query.value(0).toInt(), query.value(2).toString(),
            query.value(3).toString(), query.value(4).toInt(), query.value(5).toBool()});
    }
    endResetModel();
    recalculatePlannedHours();
}

int TaskManager::findRow(int taskId) const {
    for (int row = 0; row < m_tasks.size(); ++row) if (m_tasks[row].id == taskId) return row;
    return -1;
}

int TaskManager::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_tasks.size();
}

QVariant TaskManager::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_tasks.size()) return {};
    const auto &task = m_tasks[index.row()];
    switch (role) {
    case IdRole: return task.id;
    case NameRole: return task.name;
    case CategoryRole: return task.category;
    case MinutesRole: return task.estimatedMinutes;
    case DescriptionRole: return task.description;
    case CompletedRole: return task.isCompleted;
    case SubtaskCountRole: return task.subtasks.size();
    case CompletedSubtaskCountRole: return task.completedSubtasks();
    case EffectiveMinutesRole: return task.effectiveMinutes();
    default: return {};
    }
}

QHash<int, QByteArray> TaskManager::roleNames() const {
    return {{IdRole, "taskId"}, {NameRole, "name"}, {CategoryRole, "category"},
        {MinutesRole, "minutes"}, {DescriptionRole, "description"}, {CompletedRole, "isCompleted"},
        {SubtaskCountRole, "subtaskCount"}, {CompletedSubtaskCountRole, "completedSubtaskCount"},
        {EffectiveMinutesRole, "effectiveMinutes"}};
}

QVariantMap TaskManager::getTask(int taskId) const {
    int row = findRow(taskId);
    if (row < 0) return {};
    const auto &task = m_tasks[row];
    return {{"taskId", task.id}, {"name", task.name}, {"category", task.category},
        {"minutes", task.estimatedMinutes}, {"description", task.description},
        {"isCompleted", task.isCompleted}, {"subtaskCount", task.subtasks.size()},
        {"completedSubtaskCount", task.completedSubtasks()}, {"effectiveMinutes", task.effectiveMinutes()}};
}

QVariantList TaskManager::getSubtasks(int taskId) const {
    int row = findRow(taskId);
    if (row < 0) return {};
    QVariantList result;
    for (const auto &step : m_tasks[row].subtasks)
        result.append(QVariantMap{{"subtaskId", step.id}, {"name", step.name},
            {"description", step.description}, {"minutes", step.minutes}, {"isCompleted", step.isCompleted}});
    return result;
}

void TaskManager::notifyTask(int row) {
    emit dataChanged(index(row), index(row));
    recalculatePlannedHours();
    emit taskChanged(m_tasks[row].id);
}

bool TaskManager::addTask(const QString &name, int minutes, const QString &category, const QString &description) {
    if (name.trimmed().isEmpty() || minutes < 1 || (category != "Work" && category != "Health" && category != "Personal"))
        return fail("Enter a task title, positive duration, and valid category.");
    QSqlQuery query(m_db);
    query.prepare("INSERT INTO tasks (name, category, minutes, description, completed) VALUES (?, ?, ?, ?, 0)");
    query.addBindValue(name.trimmed());
    query.addBindValue(category);
    query.addBindValue(minutes);
    query.addBindValue(description.trimmed());
    if (!query.exec()) return fail("Could not save the task. Please try again.");
    Task task;
    task.id = query.lastInsertId().toInt();
    task.name = name.trimmed();
    task.category = category;
    task.estimatedMinutes = minutes;
    task.description = description.trimmed();
    beginInsertRows({}, m_tasks.size(), m_tasks.size());
    m_tasks.append(task);
    endInsertRows();
    recalculatePlannedHours();
    return true;
}

bool TaskManager::saveSubtasks(int taskId, const QVariantList &steps) {
    const int row = findRow(taskId);
    if (row < 0) return fail("This task no longer exists.");
    QString error;
    if (!validateBreakdown(QJsonArray::fromVariantList(steps), &error)) return fail(error);
    if (!m_db.transaction()) return fail("Could not start saving the breakdown. Please try again.");
    QSqlQuery query(m_db);
    auto rollback = [this]() {
        m_db.rollback();
        return fail("Could not save the breakdown. Your previous subtasks are unchanged.");
    };
    query.prepare("DELETE FROM subtasks WHERE parent_task_id = ?");
    query.addBindValue(taskId);
    if (!query.exec()) return rollback();
    QVector<Subtask> saved;
    for (int position = 0; position < steps.size(); ++position) {
        const auto step = steps[position].toMap();
        query.prepare("INSERT INTO subtasks (parent_task_id, position, name, description, minutes, completed) "
                      "VALUES (?, ?, ?, ?, ?, 0)");
        query.addBindValue(taskId);
        query.addBindValue(position);
        query.addBindValue(step["name"].toString().trimmed());
        query.addBindValue(step["description"].toString().trimmed());
        query.addBindValue(step["minutes"].toInt());
        if (!query.exec()) return rollback();
        saved.append({query.lastInsertId().toInt(), step["name"].toString().trimmed(),
            step["description"].toString().trimmed(), step["minutes"].toInt(), false});
    }
    query.prepare("UPDATE tasks SET completed = 0 WHERE id = ?");
    query.addBindValue(taskId);
    if (!query.exec() || !m_db.commit()) return rollback();
    m_tasks[row].subtasks = saved;
    m_tasks[row].isCompleted = false;
    notifyTask(row);
    return true;
}

bool TaskManager::toggleSubtask(int taskId, int subtaskId) {
    const int row = findRow(taskId);
    if (row < 0) return fail("This task no longer exists.");
    auto changed = m_tasks[row].subtasks;
    bool found = false;
    for (auto &step : changed) if (step.id == subtaskId) {
        step.isCompleted = !step.isCompleted;
        found = true;
    }
    if (!found) return fail("This subtask no longer exists.");
    bool allCompleted = true;
    for (const auto &step : changed) allCompleted = allCompleted && step.isCompleted;
    if (!m_db.transaction()) return fail("Could not update completion. Please try again.");
    QSqlQuery query(m_db);
    query.prepare("UPDATE subtasks SET completed = 1 - completed WHERE id = ? AND parent_task_id = ?");
    query.addBindValue(subtaskId);
    query.addBindValue(taskId);
    bool success = query.exec();
    query.prepare("UPDATE tasks SET completed = ? WHERE id = ?");
    query.addBindValue(allCompleted ? 1 : 0);
    query.addBindValue(taskId);
    if (!success || !query.exec() || !m_db.commit()) {
        m_db.rollback();
        return fail("Could not update completion. Please try again.");
    }
    m_tasks[row].subtasks = changed;
    m_tasks[row].isCompleted = allCompleted;
    notifyTask(row);
    return true;
}

bool TaskManager::toggleTaskById(int taskId) {
    const int row = findRow(taskId);
    if (row < 0) return fail("This task no longer exists.");
    const bool completed = !m_tasks[row].isCompleted;
    if (!m_db.transaction()) return fail("Could not update completion. Please try again.");
    QSqlQuery query(m_db);
    query.prepare("UPDATE tasks SET completed = ? WHERE id = ?");
    query.addBindValue(completed ? 1 : 0);
    query.addBindValue(taskId);
    bool success = query.exec();
    query.prepare("UPDATE subtasks SET completed = ? WHERE parent_task_id = ?");
    query.addBindValue(completed ? 1 : 0);
    query.addBindValue(taskId);
    if (!success || !query.exec() || !m_db.commit()) {
        m_db.rollback();
        return fail("Could not update completion. Please try again.");
    }
    m_tasks[row].isCompleted = completed;
    for (auto &step : m_tasks[row].subtasks) step.isCompleted = completed;
    notifyTask(row);
    return true;
}

void TaskManager::toggleTask(int row) {
    if (row >= 0 && row < m_tasks.size()) toggleTaskById(m_tasks[row].id);
}

void TaskManager::deleteTask(int row) {
    if (row < 0 || row >= m_tasks.size()) return;
    deleteTaskById(m_tasks[row].id);
}

bool TaskManager::deleteTaskById(int id) {
    const int row = findRow(id);
    if (row < 0) return fail("This task no longer exists.");
    if (!m_db.transaction()) return fail("Could not delete the task.");
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM subtasks WHERE parent_task_id = ?");
    query.addBindValue(id);
    bool success = query.exec();
    query.prepare("DELETE FROM tasks WHERE id = ?");
    query.addBindValue(id);
    if (!success || !query.exec() || !m_db.commit()) {
        m_db.rollback();
        return fail("Could not delete the task. Please try again.");
    }
    beginRemoveRows({}, row, row);
    m_tasks.removeAt(row);
    endRemoveRows();
    recalculatePlannedHours();
    emit taskRemoved(id);
    return true;
}

void TaskManager::setTargetHours(double hours) {
    if (!std::isfinite(hours) || hours < 0 || qFuzzyCompare(m_targetHours, hours)) return;
    QSqlQuery query(m_db);
    query.prepare("INSERT OR REPLACE INTO settings (key, value) VALUES ('targetHours', ?)");
    query.addBindValue(QString::number(hours));
    if (!query.exec()) { fail("Could not save the focus target."); return; }
    m_targetHours = hours;
    emit targetHoursChanged();
}

void TaskManager::recalculatePlannedHours() {
    int minutes = 0;
    for (const auto &task : m_tasks) minutes += task.effectiveMinutes();
    const double hours = minutes / 60.0;
    if (!qFuzzyCompare(m_totalPlannedHours, hours)) {
        m_totalPlannedHours = hours;
        emit totalPlannedHoursChanged();
    }
}
