#pragma once
#include <QAbstractListModel>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QVector>
#include <QString>
#include <QDebug>

struct Task {
    int id;
    QString name;
    QString category;
    int estimatedMinutes;
    QString description;
    bool isCompleted;

    Task(int t_id = 0,
         QString t_name = "",
         QString t_category = "Work",
         int t_minutes = 0,
         QString t_desc = "",
         bool t_completed = false)
        : id(t_id),
        name(t_name),
        category(t_category),
        estimatedMinutes(t_minutes),
        description(t_desc),
        isCompleted(t_completed) {}
};

class TaskManager : public QAbstractListModel {
    Q_OBJECT
    Q_DISABLE_COPY(TaskManager)

    Q_PROPERTY(double targetHours READ targetHours WRITE setTargetHours NOTIFY targetHoursChanged)
    Q_PROPERTY(double totalPlannedHours READ totalPlannedHours NOTIFY totalPlannedHoursChanged)

public:
    enum TaskRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        CategoryRole,
        MinutesRole,
        DescriptionRole,
        CompletedRole
    };

    explicit TaskManager(QObject *parent = nullptr);
    ~TaskManager() override = default; // Defined inline as default here

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void addTask(const QString &name, int minutes, const QString &category);
    Q_INVOKABLE void toggleTask(int index);
    Q_INVOKABLE void deleteTask(int index);

    double totalPlannedHours() const { return m_totalPlannedHours; }
    double targetHours() const { return m_targetHours; }
    void setTargetHours(double hours);

signals:
    void totalPlannedHoursChanged();
    void targetHoursChanged();

private:
    void initDatabase();
    void loadTasksFromDb();
    void recalculatePlannedHours();

    QVector<Task> m_tasks;
    double m_targetHours = 8.0;
    double m_totalPlannedHours = 0.0;
    QSqlDatabase m_db;
};