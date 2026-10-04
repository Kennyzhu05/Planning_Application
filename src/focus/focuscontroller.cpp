#include "focuscontroller.h"

#if defined(Q_OS_ANDROID)
#include <QCoreApplication>
#include <QJniObject>
#include <QJsonDocument>
#include <QJsonObject>

namespace {
constexpr auto AndroidFocus = "org/dailyplanner/focus/FocusBridge";
QJniObject androidContext()
{
    return QNativeInterface::QAndroidApplication::context();
}
}
#endif

FocusController::FocusController(QObject *parent)
    : QObject(parent)
{
    m_clock.start();
    m_timer.setInterval(1000);

    connect(&m_timer, &QTimer::timeout, this, [this]() {
#if defined(Q_OS_ANDROID)
        refreshAndroid();
#else
        if (running())
            handleEvents(m_engine.tick(m_clock.elapsed()));
#endif
    });
#if defined(Q_OS_ANDROID)
    // UI polling is disposable: Android's service continues without this timer.
    m_timer.start();
    refreshAndroid();
#endif
}

FocusEngine::Snapshot FocusController::snapshot() const
{
#if defined(Q_OS_ANDROID)
    return m_androidSnapshot;
#else
    return m_engine.snapshot();
#endif
}

bool FocusController::running() const
{
    return m_starting || snapshot().status == FocusEngine::Status::Running;
}

bool FocusController::timed() const
{
    return snapshot().mode == FocusEngine::Mode::Timed;
}

QString FocusController::status() const
{
    if (m_starting) return QStringLiteral("Starting");
    switch (snapshot().status) {
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
    return snapshot().plannedMs / 1000;
}

qint64 FocusController::elapsedSeconds() const
{
    return snapshot().elapsedMs / 1000;
}

qint64 FocusController::remainingSeconds() const
{
    const auto snapshot = this->snapshot();

    if (snapshot.mode != FocusEngine::Mode::Timed)
        return 0;

    return (snapshot.plannedMs - snapshot.elapsedMs + 999) / 1000;
}

qint64 FocusController::phoneUseSeconds() const
{
    return snapshot().phoneUseMs / 1000;
}

qint64 FocusController::currentUnlockSeconds() const
{
    return snapshot().currentUnlockMs / 1000;
}

bool FocusController::phoneInUse() const
{
#if defined(Q_OS_ANDROID)
    return snapshot().phoneInUse;
#else
    return m_simulatedPhoneInUse;
#endif
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
    if (hours < 0 || hours > 24 || minutes < 0 || minutes > 59) {
        m_error = QStringLiteral("Choose a duration from 1 minute to 24 hours.");
        emit stateChanged();
        return false;
    }

    const int totalMinutes = hours * 60 + minutes;

    if (totalMinutes < 1 || totalMinutes > 1440) {
        m_error = QStringLiteral("Choose a duration from 1 minute to 24 hours.");
        emit stateChanged();
        return false;
    }

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
#if defined(Q_OS_ANDROID)
    const auto context = androidContext();
    if (!context.isValid()) {
        m_error = QStringLiteral("Open DailyPlanner before starting focus.");
        emit stateChanged();
        return false;
    }
    const auto result = QJniObject::callStaticObjectMethod(
        AndroidFocus, "requestStart", "(Landroid/content/Context;J)Ljava/lang/String;",
        context.object<jobject>(), static_cast<jlong>(durationMs));
    if (!result.isValid()) {
        m_error = QStringLiteral("Android focus monitoring is unavailable. Rebuild with the Android package files included.");
        emit stateChanged();
        return false;
    }
    const QString error = result.toString();
    refreshAndroid();
    if (!error.isEmpty()) {
        m_error = error;
        emit stateChanged();
    }
    return error.isEmpty();
#else
    if (!m_engine.start(mode, durationMs, m_clock.elapsed(),
                        m_simulatedPhoneInUse)) {
        m_error = QStringLiteral("A focus session is already active.");
        emit stateChanged();
        return false;
    }

    m_error.clear();
    m_warningLevel = 0;
    m_timer.start();
    emit stateChanged();
    return true;
#endif
}

void FocusController::stop()
{
#if defined(Q_OS_ANDROID)
    const auto context = androidContext();
    if (context.isValid())
        QJniObject::callStaticMethod<void>(AndroidFocus, "requestStop",
            "(Landroid/content/Context;)V", context.object<jobject>());
    refreshAndroid();
#else
    m_error.clear();
    if (running())
        handleEvents(m_engine.stop(m_clock.elapsed()));
#endif
}

void FocusController::setSimulatedPhoneInUse(bool inUse)
{
    if (!simulationAvailable() || m_simulatedPhoneInUse == inUse)
        return;

    m_simulatedPhoneInUse = inUse;
    m_warningLevel = 0;

    if (running()) {
        handleEvents(m_engine.setPhoneInUse(inUse, m_clock.elapsed()));
    } else {
        emit stateChanged();
    }
}

void FocusController::handleEvents(const FocusEngine::Events &events)
{
    if (events.gentleReminder) m_warningLevel = 1;
    if (events.redReminder) m_warningLevel = 2;
    if (events.sessionEnded) {
        m_warningLevel = 0;
        m_timer.stop();
    }

    emit stateChanged();

    if (events.gentleReminder)
        emit gentleReminderRequested();

    if (events.redReminder)
        emit redReminderRequested();

    if (events.sessionEnded)
        emit sessionFinished();
}

void FocusController::refresh()
{
#if defined(Q_OS_ANDROID)
    refreshAndroid();
#else
    if (running()) handleEvents(m_engine.tick(m_clock.elapsed()));
#endif
}

void FocusController::refreshAndroid()
{
#if defined(Q_OS_ANDROID)
    const auto context = androidContext();
    if (!context.isValid()) return;
    const auto result = QJniObject::callStaticObjectMethod(AndroidFocus, "snapshot",
        "(Landroid/content/Context;)Ljava/lang/String;", context.object<jobject>());
    const auto document = QJsonDocument::fromJson(result.toString().toUtf8());
    if (!result.isValid() || !document.isObject() || !document.object().contains("status")) {
        m_error = QStringLiteral("Could not read Android focus monitoring. Rebuild the Android application.");
        emit stateChanged();
        return;
    }
    const auto data = document.object();
    const bool wasRunning = running();
    const int oldWarning = m_warningLevel;
    const QString state = data.value("status").toString();
    m_starting = state == QStringLiteral("Starting");
    m_androidSnapshot.status = state == QStringLiteral("Running") ? FocusEngine::Status::Running
        : state == QStringLiteral("Completed") ? FocusEngine::Status::Completed
        : state == QStringLiteral("Stopped") ? FocusEngine::Status::Stopped
        : state == QStringLiteral("Interrupted") ? FocusEngine::Status::Interrupted
        : FocusEngine::Status::Idle;
    m_androidSnapshot.plannedMs = static_cast<qint64>(data.value("plannedMs").toDouble());
    m_androidSnapshot.mode = m_androidSnapshot.plannedMs > 0 ? FocusEngine::Mode::Timed : FocusEngine::Mode::OpenEnded;
    m_androidSnapshot.elapsedMs = static_cast<qint64>(data.value("elapsedMs").toDouble());
    m_androidSnapshot.phoneUseMs = static_cast<qint64>(data.value("phoneUseMs").toDouble());
    m_androidSnapshot.currentUnlockMs = static_cast<qint64>(data.value("currentUnlockMs").toDouble());
    m_androidSnapshot.phoneInUse = data.value("phoneInUse").toBool();
    m_warningLevel = data.value("warning").toInt();
    m_notificationsAllowed = data.value("notificationsAllowed").toBool();
    m_error = data.value("error").toString();
    emit stateChanged();
    if (m_warningLevel != oldWarning) {
        if (m_warningLevel == 1) emit gentleReminderRequested();
        if (m_warningLevel == 2) emit redReminderRequested();
    }
    if (wasRunning && !running()) emit sessionFinished();
#endif
}

void FocusController::openNotificationSettings()
{
#if defined(Q_OS_ANDROID)
    const auto context = androidContext();
    if (context.isValid())
        QJniObject::callStaticMethod<void>(AndroidFocus, "openNotificationSettings",
            "(Landroid/content/Context;)V", context.object<jobject>());
#endif
}

void FocusController::openBatterySettings()
{
#if defined(Q_OS_ANDROID)
    const auto context = androidContext();
    if (context.isValid())
        QJniObject::callStaticMethod<void>(AndroidFocus, "openBatterySettings",
            "(Landroid/content/Context;)V", context.object<jobject>());
#endif
}
