#include "focusengine.h"

#include <algorithm>

namespace {
constexpr FocusEngine::TimeMs MinimumUseMs = 60000;
constexpr FocusEngine::TimeMs RedIntervalMs = 300000;
constexpr FocusEngine::TimeMs MaximumDurationMs = 86400000;
}

bool FocusEngine::start(Mode mode, TimeMs plannedMs,
                        TimeMs nowMs, bool phoneInUse)
{
    if (m_snapshot.status == Status::Running || nowMs < 0)
        return false;

    if (mode != Mode::Timed && mode != Mode::OpenEnded)
        return false;

    if (mode == Mode::Timed &&
        (plannedMs < MinimumUseMs || plannedMs > MaximumDurationMs))
        return false;

    m_snapshot = Snapshot{};
    m_snapshot.mode = mode;
    m_snapshot.status = Status::Running;
    m_snapshot.plannedMs = mode == Mode::Timed ? plannedMs : 0;
    m_snapshot.phoneInUse = phoneInUse;

    m_startedAtMs = nowMs;
    m_lastUpdateMs = nowMs;
    m_finishedPhoneUseMs = 0;
    m_unlockStartedAtMs = nowMs;
    m_nextRedAtMs = RedIntervalMs;
    m_gentleShown = false;

    return true;
}

FocusEngine::Events FocusEngine::tick(TimeMs nowMs)
{
    return advance(nowMs, true);
}

FocusEngine::Events FocusEngine::setPhoneInUse(
    bool inUse, TimeMs nowMs)
{
    Events events = advance(
        nowMs, inUse && m_snapshot.phoneInUse);

    if (m_snapshot.status != Status::Running ||
        inUse == m_snapshot.phoneInUse)
        return events;

    if (inUse) {
        m_unlockStartedAtMs = m_lastUpdateMs;
    } else {
        m_finishedPhoneUseMs = m_snapshot.phoneUseMs;
    }

    m_snapshot.phoneInUse = inUse;
    m_snapshot.currentUnlockMs = 0;
    m_gentleShown = false;
    m_nextRedAtMs = RedIntervalMs;

    return events;
}

FocusEngine::Events FocusEngine::stop(
    TimeMs nowMs, Status reason)
{
    if (reason != Status::Stopped &&
        reason != Status::Interrupted)
        return Events{};

    Events events = advance(nowMs, false);

    if (m_snapshot.status == Status::Running) {
        finish(reason);
        events.sessionEnded = true;
    }

    return events;
}

FocusEngine::Snapshot FocusEngine::snapshot() const
{
    return m_snapshot;
}

FocusEngine::Events FocusEngine::advance(
    TimeMs nowMs, bool issueReminders)
{
    Events events;

    if (m_snapshot.status != Status::Running)
        return events;

    nowMs = std::max(nowMs, m_lastUpdateMs);

    TimeMs elapsedMs = nowMs - m_startedAtMs;

    if (m_snapshot.mode == Mode::Timed) {
        elapsedMs = std::min(
            elapsedMs, m_snapshot.plannedMs);
    }

    m_lastUpdateMs = m_startedAtMs + elapsedMs;
    m_snapshot.elapsedMs = elapsedMs;

    m_snapshot.currentUnlockMs = m_snapshot.phoneInUse
        ? m_lastUpdateMs - m_unlockStartedAtMs
        : 0;

    const TimeMs countedCurrentUse =
        m_snapshot.currentUnlockMs >= MinimumUseMs
        ? m_snapshot.currentUnlockMs
        : 0;

    m_snapshot.phoneUseMs =
        m_finishedPhoneUseMs + countedCurrentUse;

    if (m_snapshot.mode == Mode::Timed &&
        elapsedMs >= m_snapshot.plannedMs) {
        finish(Status::Completed);
        events.sessionEnded = true;
        return events;
    }

    if (!issueReminders || !m_snapshot.phoneInUse)
        return events;

    if (!m_gentleShown &&
        m_snapshot.currentUnlockMs >= MinimumUseMs) {
        m_gentleShown = true;
        events.gentleReminder = true;
    }

    if (m_snapshot.currentUnlockMs >= m_nextRedAtMs) {
        events.redReminder = true;
        events.gentleReminder = false;

        m_nextRedAtMs =
            (m_snapshot.currentUnlockMs / RedIntervalMs + 1)
            * RedIntervalMs;
    }

    return events;
}

void FocusEngine::finish(Status reason)
{
    m_snapshot.status = reason;
    m_finishedPhoneUseMs = m_snapshot.phoneUseMs;
    m_snapshot.phoneInUse = false;
    m_snapshot.currentUnlockMs = 0;
}