#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QString>
#include <QTimer>

#include "focusengine.h"

class FocusController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool running READ running NOTIFY stateChanged)
    Q_PROPERTY(bool timed READ timed NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)

    Q_PROPERTY(qint64 plannedSeconds
               READ plannedSeconds NOTIFY stateChanged)
    Q_PROPERTY(qint64 elapsedSeconds
               READ elapsedSeconds NOTIFY stateChanged)
    Q_PROPERTY(qint64 remainingSeconds
               READ remainingSeconds NOTIFY stateChanged)
    Q_PROPERTY(qint64 phoneUseSeconds
               READ phoneUseSeconds NOTIFY stateChanged)
    Q_PROPERTY(qint64 currentUnlockSeconds
               READ currentUnlockSeconds NOTIFY stateChanged)

    Q_PROPERTY(bool phoneInUse
               READ phoneInUse NOTIFY stateChanged)
    Q_PROPERTY(bool simulationAvailable
               READ simulationAvailable CONSTANT)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)
    Q_PROPERTY(int warningLevel READ warningLevel NOTIFY stateChanged)
    Q_PROPERTY(bool notificationsAllowed READ notificationsAllowed NOTIFY stateChanged)

public:
    explicit FocusController(QObject *parent = nullptr);

    bool running() const;
    bool timed() const;
    QString status() const;

    qint64 plannedSeconds() const;
    qint64 elapsedSeconds() const;
    qint64 remainingSeconds() const;
    qint64 phoneUseSeconds() const;
    qint64 currentUnlockSeconds() const;

    bool phoneInUse() const;
    bool simulationAvailable() const;
    QString errorMessage() const { return m_error; }
    int warningLevel() const { return m_warningLevel; }
    bool notificationsAllowed() const { return m_notificationsAllowed; }

    Q_INVOKABLE bool startTimed(int hours, int minutes);
    Q_INVOKABLE bool startOpenEnded();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void setSimulatedPhoneInUse(bool inUse);
    Q_INVOKABLE void openNotificationSettings();
    Q_INVOKABLE void openBatterySettings();
    Q_INVOKABLE void refresh();

signals:
    void stateChanged();
    void gentleReminderRequested();
    void redReminderRequested();
    void sessionFinished();

private:
    bool start(FocusEngine::Mode mode,
               FocusEngine::TimeMs durationMs);
    void handleEvents(const FocusEngine::Events &events);
    FocusEngine::Snapshot snapshot() const;
    void refreshAndroid();

    FocusEngine m_engine;
    QElapsedTimer m_clock;
    QTimer m_timer;
    bool m_simulatedPhoneInUse = true;
    FocusEngine::Snapshot m_androidSnapshot;
    bool m_starting = false;
    bool m_notificationsAllowed = true;
    QString m_error;
    int m_warningLevel = 0;
};
