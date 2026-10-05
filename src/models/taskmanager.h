#pragma once
#include <QAbstractListModel>
#include <QSqlDatabase>
#include <QVariantMap>
#include <QDate>
#include <QSortFilterProxyModel>
#include "task.h"

class TaskManager : public QAbstractListModel {
    Q_OBJECT
    Q_DISABLE_COPY(TaskManager)
    Q_PROPERTY(double targetHours READ targetHours WRITE setTargetHours NOTIFY targetHoursChanged)
    Q_PROPERTY(double totalPlannedHours READ totalPlannedHours NOTIFY totalPlannedHoursChanged)
    Q_PROPERTY(int revision READ revision NOTIFY plannerChanged)
    Q_PROPERTY(QString todayDate READ todayDate NOTIFY plannerChanged)
    Q_PROPERTY(QAbstractItemModel *todayTasks READ todayTasks CONSTANT)
    Q_PROPERTY(QString rolloverMessage READ rolloverMessage NOTIFY rolloverNoticeChanged)
    Q_PROPERTY(bool rolloverFailed READ rolloverFailed NOTIFY rolloverNoticeChanged)
public:
    enum TaskRoles {
        IdRole = Qt::UserRole + 1, NameRole, CategoryRole, MinutesRole,
        DescriptionRole, CompletedRole, SubtaskCountRole, CompletedSubtaskCountRole, EffectiveMinutesRole,
        PlannedDateRole, GoalIdRole, GoalNameRole
    };
    explicit TaskManager(QObject *parent = nullptr, const QString &databasePath = "planner.db");
    ~TaskManager() override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    Q_INVOKABLE bool addTask(const QString &name, int minutes, const QString &category,
                            const QString &description = QString(), const QString &plannedDate = QString());
    Q_INVOKABLE bool updateTask(int taskId, const QVariantMap &details);
    Q_INVOKABLE bool setTaskDate(int taskId, const QString &plannedDate);
    Q_INVOKABLE QVariantList tasksForDate(const QString &date) const;
    Q_INVOKABLE QVariantList goalsForDate(const QString &date) const;
    Q_INVOKABLE bool hasItemsOnDate(const QString &date) const;
    Q_INVOKABLE QVariantList getGoals() const;
    Q_INVOKABLE QVariantMap getGoal(int goalId) const;
    Q_INVOKABLE QVariantList getGoalTasks(int goalId) const;
    Q_INVOKABLE int saveGoal(const QVariantMap &details, int goalId = 0);
    Q_INVOKABLE bool toggleGoal(int goalId);
    Q_INVOKABLE bool saveGoalBreakdown(int goalId, const QVariantList &milestones, const QVariantList &steps);
    Q_INVOKABLE void refreshToday();
    Q_INVOKABLE void dismissRolloverMessage();
    Q_INVOKABLE void toggleTask(int index);
    Q_INVOKABLE void deleteTask(int index);
    Q_INVOKABLE bool deleteTaskById(int taskId);
    Q_INVOKABLE bool toggleTaskById(int taskId);
    Q_INVOKABLE QVariantMap getTask(int taskId) const;
    Q_INVOKABLE QVariantList getSubtasks(int taskId) const;
    Q_INVOKABLE bool saveSubtasks(int taskId, const QVariantList &steps);
    Q_INVOKABLE bool updateSubtasks(int taskId, const QVariantList &steps);
    Q_INVOKABLE bool toggleSubtask(int taskId, int subtaskId);
    Q_INVOKABLE void setTargetHours(double hours);
    double totalPlannedHours() const { return m_totalPlannedHours; }
    double targetHours() const { return m_targetHours; }
    int revision() const { return m_revision; }
    QString todayDate() const { return m_today.toString(Qt::ISODate); }
    QAbstractItemModel *todayTasks() const { return m_todayTasks; }
    QString rolloverMessage() const { return m_rolloverMessage; }
    bool rolloverFailed() const { return m_rolloverFailed; }
signals:
    void rolloverNoticeChanged();
    void plannerChanged();
    void goalChanged(int goalId);
    void totalPlannedHoursChanged();
    void targetHoursChanged();
    void taskChanged(int taskId);
    void taskRemoved(int taskId);
    void errorOccurred(const QString &message);
private:
    bool initDatabase(const QString &databasePath);
    void loadTasksFromDb();
    int findRow(int taskId) const;
    int findGoal(int goalId) const;
    void publishChange();
    static bool validDate(const QString &date, bool allowEmpty = true);
    void notifyTask(int row);
    bool fail(const QString &message);
    void recalculatePlannedHours();
    bool rolloverOverdueTasks(QVector<int> &changedTaskIds);
    void setRolloverNotice(const QString &message, bool failed = false);
    QVector<Task> m_tasks;
    QVector<Goal> m_goals;
    QDate m_today = QDate::currentDate();
    QDate m_lastRolloverDate;
    QString m_rolloverMessage;
    bool m_rolloverFailed = false;
    bool m_databaseReady = false;
    int m_revision = 0;
    QSortFilterProxyModel *m_todayTasks = nullptr;
    double m_targetHours = 0.0;
    double m_totalPlannedHours = 0.0;
    QSqlDatabase m_db;
};
