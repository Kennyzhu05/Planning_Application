#include "taskmanager.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>

TaskManager::TaskManager(QObject *parent) : QAbstractListModel(parent) {
    initDatabase();
    loadTasksFromDb();
}

void TaskManager::initDatabase() {
    m_db = QSqlDatabase::addDatabase("QSQLITE");
    m_db.setDatabaseName("planner.db");

    if (!m_db.open()) {
        qWarning() << "Database Error:" << m_db.lastError().text();
        return;
    }

    QSqlQuery query;
    query.exec("CREATE TABLE IF NOT EXISTS tasks ("
               "id INTEGER PRIMARY KEY AUTOINCREMENT, "
               "name TEXT, "
               "category TEXT, "
               "estimatedMinutes INTEGER, "
               "description TEXT, "
               "completed INTEGER)");
}

void TaskManager::loadTasksFromDb() {
    beginResetModel();
    m_tasks.clear();

    QSqlQuery query("SELECT id, name, category, estimatedMinutes, description, completed FROM tasks");
    while (query.next()) {
        m_tasks.append(Task(
            query.value(0).toInt(),      // id
            query.value(1).toString(),   // name
            query.value(2).toString(),   // category
            query.value(3).toInt(),      // estimatedMinutes
            query.value(4).toString(),   // description
            query.value(5).toBool()      // completed
            ));
    }
    endResetModel();
    recalculatePlannedHours();
}

int TaskManager::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_tasks.count();
}

QVariant TaskManager::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_tasks.size()) return {};
    const auto &task = m_tasks[index.row()];
    switch (role) {
    case IdRole: return task.id;
    case NameRole: return task.name;
    case CategoryRole: return task.category;
    case MinutesRole: return task.estimatedMinutes;
    case DescriptionRole: return task.description;
    case CompletedRole: return task.isCompleted;
    default: return {};
    }
}

QHash<int, QByteArray> TaskManager::roleNames() const {
    return {
        {IdRole, "taskId"}, {NameRole, "name"}, {CategoryRole, "category"},
        {MinutesRole, "minutes"}, {DescriptionRole, "description"}, {CompletedRole, "isCompleted"}
    };
}

void TaskManager::addTask(const QString &name, int minutes, const QString &category) {
    QString cleanName = name.trimmed();
    if (cleanName.isEmpty()) return;

    QSqlQuery query;
    query.prepare("INSERT INTO tasks (name, category, estimatedMinutes, description, completed) "
                  "VALUES (:name, :category, :minutes, :description, 0)");
    query.bindValue(":name", cleanName);
    query.bindValue(":category", category);
    query.bindValue(":minutes", minutes);
    query.bindValue(":description", ""); // Default empty description

    if (query.exec()) {
        int newId = query.lastInsertId().toInt();

        beginInsertRows(QModelIndex(), m_tasks.size(), m_tasks.size());
        m_tasks.append(Task(newId, cleanName, category, minutes, "", false));
        endInsertRows();

        recalculatePlannedHours();
    } else {
        qWarning() << "Failed to add task to SQLite database:" << query.lastError().text();
    }
}

void TaskManager::toggleTask(int index) {
    if (index < 0 || index >= m_tasks.size()) return;
    auto &task = m_tasks[index];
    task.isCompleted = !task.isCompleted;

    QSqlQuery query;
    query.prepare("UPDATE tasks SET completed = ? WHERE id = ?");
    query.addBindValue(task.isCompleted ? 1 : 0);
    query.addBindValue(task.id);
    query.exec();

    QModelIndex modelIdx = createIndex(index, 0);
    emit dataChanged(modelIdx, modelIdx, {CompletedRole});
}

void TaskManager::deleteTask(int index) {
    if (index < 0 || index >= m_tasks.size()) return;
    QSqlQuery query;
    query.prepare("DELETE FROM tasks WHERE id = ?");
    query.addBindValue(m_tasks[index].id);

    if (query.exec()) {
        beginRemoveRows(QModelIndex(), index, index);
        m_tasks.removeAt(index);
        endRemoveRows();
        recalculatePlannedHours();
    }
}

void TaskManager::setTargetHours(double hours) {
    if (qFuzzyCompare(m_targetHours, hours)) return;
    m_targetHours = hours;
    emit targetHoursChanged();
}

void TaskManager::recalculatePlannedHours() {
    int totalMins = 0;
    for (const auto &t : std::as_const(m_tasks)) {
        totalMins += t.estimatedMinutes;
    }
    double hrs = totalMins / 60.0;
    if (!qFuzzyCompare(m_totalPlannedHours, hrs)) {
        m_totalPlannedHours = hrs;
        emit totalPlannedHoursChanged();
    }
}