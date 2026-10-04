#pragma once

#include <cstdint>

class FocusEngine
{
public:
    using TimeMs = std::int64_t;

    enum class Mode {
        Timed,
        OpenEnded
    };

    enum class Status {
        Idle,
        Running,
        Completed,
        Stopped,
        Interrupted
    };

    struct Snapshot {
        Mode mode = Mode::Timed;
        Status status = Status::Idle;
        TimeMs plannedMs = 0;
        TimeMs elapsedMs = 0;
        TimeMs phoneUseMs = 0;
        TimeMs currentUnlockMs = 0;
        bool phoneInUse = false;
    };

    struct Events {
        bool gentleReminder = false;
        bool redReminder = false;
        bool sessionEnded = false;
    };

    bool start(Mode mode, TimeMs plannedMs,
               TimeMs nowMs, bool phoneInUse);

    Events tick(TimeMs nowMs);
    Events setPhoneInUse(bool inUse, TimeMs nowMs);
    Events stop(TimeMs nowMs,
                Status reason = Status::Stopped);

    Snapshot snapshot() const;

private:
    Events advance(TimeMs nowMs, bool issueReminders);
    void finish(Status reason);

    Snapshot m_snapshot;
    TimeMs m_startedAtMs = 0;
    TimeMs m_lastUpdateMs = 0;
    TimeMs m_finishedPhoneUseMs = 0;
    TimeMs m_unlockStartedAtMs = 0;
    TimeMs m_nextRedAtMs = 300000;
    bool m_gentleShown = false;
};