#include "focuscontroller.h"

FocusController::FocusController(QObject *parent)
    : QObject(parent)
{
    m_clock.start();
    m_timer.setInterval(1000);

    connect(&m_timer, &QTimer::timeout, this, [this]() {
        if (running())
            handleEvents(m_engine.tick(m_clock.elapsed()));
    });
}

bool FocusController::running() const
{
    return m_engine.snapshot().status == FocusEngine::Status::Running;
}

bool FocusController::timed() const
{
    return m_engine.snapshot().mode == FocusEngine::Mode::Timed;
}

QString FocusController::status() const
{
    switch (m_engine.snapshot().status) {
    case FocusEngine::Status::Idle:
        return QStringLiteral("Idle");
    case FocusEngine::Status::Running:
        return QStringLiteral("Running");
    case FocusEngine::Status::Completed:
        return QStringLiteral("Completed");
    case FocusEngine::Status::Stopped:
        return QStringLiteral("Stopped");
    case FocusEngine::Status::Interrupted:
        return QStringLiteral("Interrupted");
    }

    return QStringLiteral("Unknown");
}

qint64 FocusController::plannedSeconds() const
{
    return m_engine.snapshot().plannedMs / 1000;
}

qint64 FocusController::elapsedSeconds() const
{
    return m_engine.snapshot().elapsedMs / 1000;
}

qint64 FocusController::remainingSeconds() const
{
    const auto snapshot = m_engine.snapshot();

    if (snapshot.mode != FocusEngine::Mode::Timed)
        return 0;

    return (snapshot.plannedMs - snapshot.elapsedMs + 999) / 1000;
}

qint64 FocusController::phoneUseSeconds() const
{
    return m_engine.snapshot().phoneUseMs / 1000;
}

qint64 FocusController::currentUnlockSeconds() const
{
    return m_engine.snapshot().currentUnlockMs / 1000;
}

bool FocusController::phoneInUse() const
{
    return simulationAvailable() && m_simulatedPhoneInUse;
}

bool FocusController::simulationAvailable() const
{
#if defined(Q_OS_ANDROID)
    return false;
#else
    return true;
#endif
}

bool FocusController::startTimed(int hours, int minutes)
{
    if (hours < 0 || hours > 24 || minutes < 0 || minutes > 59)
        return false;

    const int totalMinutes = hours * 60 + minutes;

    if (totalMinutes < 1 || totalMinutes > 1440)
        return false;

    return start(FocusEngine::Mode::Timed,
                 static_cast<FocusEngine::TimeMs>(totalMinutes) * 60000);
}

bool FocusController::startOpenEnded()
{
    return start(FocusEngine::Mode::OpenEnded, 0);
}

bool FocusController::start(
    FocusEngine::Mode mode, FocusEngine::TimeMs durationMs)
{
    if (!simulationAvailable())
        return false;

    if (!m_engine.start(mode, durationMs, m_clock.elapsed(),
                        m_simulatedPhoneInUse))
        return false;

    m_timer.start();
    emit stateChanged();
    return true;
}

void FocusController::stop()
{
    if (running())
        handleEvents(m_engine.stop(m_clock.elapsed()));
}

void FocusController::setSimulatedPhoneInUse(bool inUse)
{
    if (!simulationAvailable() || m_simulatedPhoneInUse == inUse)
        return;

    m_simulatedPhoneInUse = inUse;

    if (running()) {
        handleEvents(m_engine.setPhoneInUse(inUse, m_clock.elapsed()));
    } else {
        emit stateChanged();
    }
}

void FocusController::handleEvents(const FocusEngine::Events &events)
{
    if (events.sessionEnded)
        m_timer.stop();

    emit stateChanged();

    if (events.gentleReminder)
        emit gentleReminderRequested();

    if (events.redReminder)
        emit redReminderRequested();

    if (events.sessionEnded)
        emit sessionFinished();
}