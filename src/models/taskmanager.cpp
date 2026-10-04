#include "taskmanager.h"
#include "breakdownvalidation.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QUuid>
#include <QSet>
#include <cmath>

TaskManager::TaskManager(QObject *parent, const QString &databasePath) : QAbstractListModel(parent) {
    if (initDatabase(databasePath)) loadTasksFromDb();
    m_todayTasks = new QSortFilterProxyModel(this);
    m_todayTasks->setSourceModel(this);
    m_todayTasks->setFilterRole(PlannedDateRole);
    m_todayTasks->setFilterFixedString(todayDate());
    connect(this, &TaskManager::plannerChanged, m_todayTasks, [this]() {
        m_todayTasks->setFilterFixedString(todayDate());
    });
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
    if (!query.exec("PRAGMA foreign_keys = ON") || !m_db.transaction())
        return fail("Cannot initialize the planner database.");
    auto migrationFailure = [this]() {
        m_db.rollback();
        return fail("Could not upgrade the planner database. Existing data is unchanged.");
    };
    const QStringList schema = {
        "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)",
        "CREATE TABLE IF NOT EXISTS goals (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, "
        "description TEXT NOT NULL DEFAULT '', success_criteria TEXT NOT NULL DEFAULT '', target_date TEXT, "
        "category TEXT NOT NULL DEFAULT 'Personal', starting_point TEXT NOT NULL DEFAULT '', "
        "weekly_hours REAL NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0, milestones TEXT NOT NULL DEFAULT '[]')",
        "CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, "
        "category TEXT, minutes INTEGER, description TEXT, completed INTEGER)",
        "CREATE TABLE IF NOT EXISTS subtasks (id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "parent_task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, "
        "position INTEGER NOT NULL, name TEXT NOT NULL, description TEXT NOT NULL, "
        "minutes INTEGER NOT NULL CHECK(minutes BETWEEN 1 AND 120), "
        "completed INTEGER NOT NULL DEFAULT 0, UNIQUE(parent_task_id, position))"
    };
    for (const auto &statement : schema)
        if (!query.exec(statement)) return migrationFailure();

    // Older databases used estimatedMinutes. CREATE TABLE IF NOT EXISTS does
    // not update existing columns, so retain their values by renaming in place.
    const QSqlRecord taskColumns = m_db.record("tasks");
    if (!taskColumns.contains("minutes")) {
        if (!taskColumns.contains("estimatedMinutes"))
            return migrationFailure();
        if (!query.exec("ALTER TABLE tasks RENAME COLUMN estimatedMinutes TO minutes"))
            return migrationFailure();
    }

    // Only the first upgrade assigns dates. Intentionally unscheduled goal tasks
    // remain NULL on every subsequent startup.
    if (!taskColumns.contains("planned_date")) {
        if (!query.exec("ALTER TABLE tasks ADD COLUMN planned_date TEXT")) return migrationFailure();
        query.prepare("UPDATE tasks SET planned_date = ?");
        query.addBindValue(todayDate());
        if (!query.exec()) return migrationFailure();
    }
    if (!taskColumns.contains("goal_id") && !query.exec(
            "ALTER TABLE tasks ADD COLUMN goal_id INTEGER REFERENCES goals(id) ON DELETE SET NULL"))
        return migrationFailure();
    if (!taskColumns.contains("goal_position") && !query.exec(
            "ALTER TABLE tasks ADD COLUMN goal_position INTEGER NOT NULL DEFAULT 0"))
        return migrationFailure();
    if (!query.exec("CREATE INDEX IF NOT EXISTS tasks_planned_date ON tasks(planned_date)")
        || !query.exec("CREATE INDEX IF NOT EXISTS tasks_goal_id ON tasks(goal_id)")
        || !m_db.commit()) return migrationFailure();

    query.exec("SELECT value FROM settings WHERE key = 'targetHours'");
    if (query.next()) m_targetHours = query.value(0).toDouble();
    return true;
}

void TaskManager::loadTasksFromDb() {
    beginResetModel();
    m_tasks.clear();
    m_goals.clear();
    QSqlQuery query(m_db);
    query.exec("SELECT id, name, description, success_criteria, target_date, category, starting_point, "
               "weekly_hours, completed, milestones FROM goals ORDER BY id");
    while (query.next()) {
        Goal goal;
        goal.id = query.value(0).toInt();
        goal.name = query.value(1).toString();
        goal.description = query.value(2).toString();
        goal.successCriteria = query.value(3).toString();
        goal.targetDate = query.value(4).toString();
        goal.category = query.value(5).toString();
        goal.startingPoint = query.value(6).toString();
        goal.weeklyHours = query.value(7).toDouble();
        goal.isCompleted = query.value(8).toBool();
        for (const auto &milestone : QJsonDocument::fromJson(query.value(9).toByteArray()).array())
            goal.milestones.append(milestone.toString());
        m_goals.append(goal);
    }
    query.exec("SELECT id, name, category, minutes, description, completed, planned_date, goal_id, "
               "goal_position FROM tasks ORDER BY id");
    while (query.next()) {
        Task task;
        task.id = query.value(0).toInt();
        task.name = query.value(1).toString();
        task.category = query.value(2).toString();
        task.estimatedMinutes = query.value(3).toInt();
        task.description = query.value(4).toString();
        task.isCompleted = query.value(5).toBool();
        task.plannedDate = query.value(6).toString();
        task.goalId = query.value(7).toInt();
        task.goalPosition = query.value(8).toInt();
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
    publishChange();
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
    case PlannedDateRole: return task.plannedDate;
    case GoalIdRole: return task.goalId;
    case GoalNameRole: return getGoal(task.goalId).value("name");
    default: return {};
    }
}

QHash<int, QByteArray> TaskManager::roleNames() const {
    return {{IdRole, "taskId"}, {NameRole, "name"}, {CategoryRole, "category"},
        {MinutesRole, "minutes"}, {DescriptionRole, "description"}, {CompletedRole, "isCompleted"},
        {SubtaskCountRole, "subtaskCount"}, {CompletedSubtaskCountRole, "completedSubtaskCount"},
        {EffectiveMinutesRole, "effectiveMinutes"}, {PlannedDateRole, "plannedDate"},
        {GoalIdRole, "goalId"}, {GoalNameRole, "goalName"}};
}

QVariantMap TaskManager::getTask(int taskId) const {
    int row = findRow(taskId);
    if (row < 0) return {};
    const auto &task = m_tasks[row];
    return {{"taskId", task.id}, {"name", task.name}, {"category", task.category},
        {"minutes", task.estimatedMinutes}, {"description", task.description},
        {"isCompleted", task.isCompleted}, {"subtaskCount", task.subtasks.size()},
        {"completedSubtaskCount", task.completedSubtasks()}, {"effectiveMinutes", task.effectiveMinutes()},
        {"plannedDate", task.plannedDate}, {"goalId", task.goalId},
        {"goalName", getGoal(task.goalId).value("name")}};
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
    publishChange();
}

bool TaskManager::addTask(const QString &name, int minutes, const QString &category, const QString &description,
                          const QString &plannedDate) {
    const QString date = plannedDate.isEmpty() ? todayDate() : plannedDate;
    if (name.trimmed().isEmpty() || minutes < 1 || (category != "Work" && category != "Health" && category != "Personal"))
        return fail("Enter a task title, positive duration, and valid category.");
    if (!validDate(date, false)) return fail("Choose a valid planned date.");
    QSqlQuery query(m_db);
    query.prepare("INSERT INTO tasks (name, category, minutes, description, completed, planned_date) VALUES (?, ?, ?, ?, 0, ?)");
    query.addBindValue(name.trimmed());
    query.addBindValue(category);
    query.addBindValue(minutes);
    query.addBindValue(description.trimmed());
    query.addBindValue(date);
    if (!query.exec()) return fail("Could not save the task. Please try again.");
    Task task;
    task.id = query.lastInsertId().toInt();
    task.name = name.trimmed();
    task.category = category;
    task.estimatedMinutes = minutes;
    task.description = description.trimmed();
    task.plannedDate = date;
    beginInsertRows({}, m_tasks.size(), m_tasks.size());
    m_tasks.append(task);
    endInsertRows();
    recalculatePlannedHours();
    publishChange();
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

bool TaskManager::updateSubtasks(int taskId, const QVariantList &steps) {
    const int row = findRow(taskId);
    if (row < 0) return fail("This task no longer exists.");
    QString error;
    if (!validateBreakdown(QJsonArray::fromVariantList(steps), &error)) return fail(error);

    // Only IDs belonging to this parent can be retained. Completion comes from
    // the stored checklist, never from the editable draft supplied by QML.
    QSet<int> retained;
    QVector<Subtask> changed;
    for (const auto &value : steps) {
        const auto step = value.toMap();
        bool validId = false;
        const int id = step.value("subtaskId", 0).toInt(&validId);
        if (!validId || id < 0 || retained.contains(id))
            return fail("This checklist contains an invalid or duplicate step.");
        bool completed = false;
        if (id > 0) {
            bool found = false;
            for (const auto &existing : m_tasks[row].subtasks) {
                if (existing.id != id) continue;
                completed = existing.isCompleted;
                found = true;
                break;
            }
            if (!found) return fail("A step no longer belongs to this task. Reopen the editor.");
            retained.insert(id);
        }
        changed.append({id, step["name"].toString().trimmed(),
            step["description"].toString().trimmed(), step["minutes"].toInt(), completed});
    }
    if (!m_db.transaction()) return fail("Could not start saving your changes. Please try again.");
    QSqlQuery query(m_db);
    auto rollback = [this]() {
        m_db.rollback();
        return fail("Could not save your changes. Your previous subtasks and progress are unchanged.");
    };
    for (const auto &existing : m_tasks[row].subtasks) {
        if (retained.contains(existing.id)) continue;
        query.prepare("DELETE FROM subtasks WHERE id = ? AND parent_task_id = ?");
        query.addBindValue(existing.id);
        query.addBindValue(taskId);
        if (!query.exec()) return rollback();
    }
    // Free the final positions before rearranging rows: the table enforces
    // UNIQUE(parent_task_id, position), so directly swapping 0 and 1 fails.
    // Negative IDs are unique temporary positions, hidden by this transaction.
    query.prepare("UPDATE subtasks SET position = -id WHERE parent_task_id = ?");
    query.addBindValue(taskId);
    if (!query.exec()) return rollback();
    bool allCompleted = true;
    for (int position = 0; position < changed.size(); ++position) {
        auto &step = changed[position];
        if (step.id > 0) {
            query.prepare("UPDATE subtasks SET position = ?, name = ?, description = ?, minutes = ? "
                          "WHERE id = ? AND parent_task_id = ?");
            query.addBindValue(position);
            query.addBindValue(step.name);
            query.addBindValue(step.description);
            query.addBindValue(step.minutes);
            query.addBindValue(step.id);
            query.addBindValue(taskId);
            if (!query.exec() || query.numRowsAffected() != 1) return rollback();
        } else {
            query.prepare("INSERT INTO subtasks (parent_task_id, position, name, description, minutes, completed) "
                          "VALUES (?, ?, ?, ?, ?, 0)");
            query.addBindValue(taskId);
            query.addBindValue(position);
            query.addBindValue(step.name);
            query.addBindValue(step.description);
            query.addBindValue(step.minutes);
            if (!query.exec()) return rollback();
            step.id = query.lastInsertId().toInt();
        }
        allCompleted = allCompleted && step.isCompleted;
    }
    query.prepare("UPDATE tasks SET completed = ? WHERE id = ?");
    query.addBindValue(allCompleted ? 1 : 0);
    query.addBindValue(taskId);
    if (!query.exec() || !m_db.commit()) return rollback();
    m_tasks[row].subtasks = changed;
    m_tasks[row].isCompleted = allCompleted;
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
    publishChange();
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
    for (const auto &task : m_tasks)
        if (task.plannedDate == todayDate()) minutes += task.effectiveMinutes();
    const double hours = minutes / 60.0;
    if (!qFuzzyCompare(m_totalPlannedHours, hours)) {
        m_totalPlannedHours = hours;
        emit totalPlannedHoursChanged();
    }
}
