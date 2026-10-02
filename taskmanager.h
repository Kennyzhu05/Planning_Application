#pragma once
#include <QAbstractListModel>
#include <QSqlDatabase>
#include <QVariantMap>
#include "task.h"

class TaskManager : public QAbstractListModel {
    Q_OBJECT
    Q_DISABLE_COPY(TaskManager)
    Q_PROPERTY(double targetHours READ targetHours WRITE setTargetHours NOTIFY targetHoursChanged)
    Q_PROPERTY(double totalPlannedHours READ totalPlannedHours NOTIFY totalPlannedHoursChanged)
public:
    enum TaskRoles {
        IdRole = Qt::UserRole + 1, NameRole, CategoryRole, MinutesRole,
        DescriptionRole, CompletedRole, SubtaskCountRole, CompletedSubtaskCountRole, EffectiveMinutesRole
    };
    explicit TaskManager(QObject *parent = nullptr, const QString &databasePath = "planner.db");
    ~TaskManager() override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    Q_INVOKABLE bool addTask(const QString &name, int minutes, const QString &category,
                            const QString &description = QString());
    Q_INVOKABLE void toggleTask(int index);
    Q_INVOKABLE void deleteTask(int index);
    Q_INVOKABLE bool deleteTaskById(int taskId);
    Q_INVOKABLE bool toggleTaskById(int taskId);
    Q_INVOKABLE QVariantMap getTask(int taskId) const;
    Q_INVOKABLE QVariantList getSubtasks(int taskId) const;
    Q_INVOKABLE bool saveSubtasks(int taskId, const QVariantList &steps);
    Q_INVOKABLE bool toggleSubtask(int taskId, int subtaskId);
    Q_INVOKABLE void setTargetHours(double hours);
    double totalPlannedHours() const { return m_totalPlannedHours; }
    double targetHours() const { return m_targetHours; }
signals:
    void totalPlannedHoursChanged();
    void targetHoursChanged();
    void taskChanged(int taskId);
    void taskRemoved(int taskId);
    void errorOccurred(const QString &message);
private:
    bool initDatabase(const QString &databasePath);
    void loadTasksFromDb();
    int findRow(int taskId) const;
    void notifyTask(int row);
    bool fail(const QString &message);
    void recalculatePlannedHours();
    QVector<Task> m_tasks;
    double m_targetHours = 0.0;
    double m_totalPlannedHours = 0.0;
    QSqlDatabase m_db;
};
