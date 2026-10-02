#include "focusengine.h"

#include <cstdlib>
#include <iostream>

void check(bool condition, const char *message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(EXIT_FAILURE);
    }
}

int main()
{
    using Engine = FocusEngine;

    // A 59-second unlock must not count.
    Engine shortUse;
    check(shortUse.start(Engine::Mode::OpenEnded, 0, 0, true),
          "Open-ended session should start");

    const auto shortEvents = shortUse.tick(59000);

    check(shortUse.snapshot().phoneUseMs == 0,
          "59 seconds must count as zero");
    check(!shortEvents.gentleReminder,
          "59 seconds must not trigger a reminder");

    shortUse.setPhoneInUse(false, 59000);

    check(shortUse.snapshot().phoneUseMs == 0,
          "Locking before one minute must discard that usage");

    // At 60 seconds, the entire interval must count.
    Engine qualifiedUse;
    check(qualifiedUse.start(Engine::Mode::OpenEnded, 0, 0, true),
          "Second session should start");

    const auto minuteEvents = qualifiedUse.tick(60000);

    check(qualifiedUse.snapshot().phoneUseMs == 60000,
          "At one minute, the full minute must count");
    check(minuteEvents.gentleReminder,
          "One minute must trigger the gentle reminder");

    const auto laterEvents = qualifiedUse.tick(80000);

    check(qualifiedUse.snapshot().phoneUseMs == 80000,
          "One minute twenty seconds must count in full");
    check(!laterEvents.gentleReminder,
          "Gentle reminder must not repeat in the same unlock");

    qualifiedUse.setPhoneInUse(false, 80000);

    check(qualifiedUse.snapshot().phoneUseMs == 80000,
          "Locking must preserve qualified usage");
    check(qualifiedUse.snapshot().currentUnlockMs == 0,
          "Locking must reset the current unlock");
    // Three separate two-minute unlocks count as six minutes.
    Engine accumulatedUse;
    check(accumulatedUse.start(Engine::Mode::OpenEnded, 0, 0, false),
          "Accumulation session should start");

    for (int i = 0; i < 3; ++i) {
        const Engine::TimeMs unlockedAt = i * 180000;

        accumulatedUse.setPhoneInUse(true, unlockedAt);
        const auto events = accumulatedUse.tick(unlockedAt + 120000);

        check(!events.redReminder,
              "Separate two-minute unlocks must not trigger red");
        accumulatedUse.setPhoneInUse(false, unlockedAt + 120000);
    }

    check(accumulatedUse.snapshot().phoneUseMs == 360000,
          "Three two-minute unlocks must total six minutes");

    // Red reminders occur at five and ten continuous minutes.
    Engine reminders;
    check(reminders.start(Engine::Mode::OpenEnded, 0, 0, true),
          "Reminder session should start");

    reminders.tick(60000);

    check(reminders.tick(300000).redReminder,
          "Five continuous minutes must trigger red");
    check(!reminders.tick(301000).redReminder,
          "Red must not repeat immediately");
    check(reminders.tick(600000).redReminder,
          "Ten continuous minutes must trigger red again");

    reminders.setPhoneInUse(false, 600000);
    reminders.setPhoneInUse(true, 660000);

    const auto newUnlockEvents = reminders.tick(720000);

    check(newUnlockEvents.gentleReminder,
          "A new unlock must restart the gentle reminder");
    check(!newUnlockEvents.redReminder,
          "A new unlock must reset the red reminder threshold");
    check(reminders.tick(960000).redReminder,
          "Five minutes after the new unlock must trigger red");

    // A late update must stop exactly at the planned duration.
    Engine timed;
    check(timed.start(Engine::Mode::Timed, 120000, 10000, true),
          "Two-minute timed session should start");

    const auto completion = timed.tick(200000);

    check(completion.sessionEnded,
          "Timed session must end automatically");
    check(timed.snapshot().status == Engine::Status::Completed,
          "Timed session must be marked completed");
    check(timed.snapshot().elapsedMs == 120000,
          "Focus time must stop at the planned duration");
    check(timed.snapshot().phoneUseMs == 120000,
          "Phone usage must not include time after completion");
    check(!completion.gentleReminder && !completion.redReminder,
          "An ended session must not issue usage reminders");
    check(!timed.tick(210000).sessionEnded,
          "Completion must only be reported once");

    // Manual ending preserves counted usage.
    Engine manual;
    check(manual.start(Engine::Mode::OpenEnded, 0, 0, true),
          "Manual session should start");

    const auto stopped = manual.stop(80000);

    check(stopped.sessionEnded,
          "Manual stop must report session ending");
    check(manual.snapshot().status == Engine::Status::Stopped,
          "Manual stop must preserve its ending reason");
    check(manual.snapshot().phoneUseMs == 80000,
          "Manual stop must preserve qualified phone usage");

    // Starting again clears the previous session totals.
    check(manual.start(Engine::Mode::OpenEnded, 0, 90000, true),
          "A stopped engine should allow a new session");
    check(manual.snapshot().phoneUseMs == 0,
          "A new session must reset phone usage");

    manual.stop(150000, Engine::Status::Interrupted);

    check(manual.snapshot().status == Engine::Status::Interrupted,
          "Interrupted ending must preserve its reason");

    // Timed duration must be between one minute and 24 hours.
    Engine limits;
    check(!limits.start(Engine::Mode::Timed, 59999, 0, false),
          "A duration below one minute must be rejected");
    check(!limits.start(Engine::Mode::Timed, 86400001, 0, false),
          "A duration above 24 hours must be rejected");
    check(limits.start(Engine::Mode::Timed, 60000, 0, false),
          "Exactly one minute must be accepted");
    check(!limits.start(Engine::Mode::OpenEnded, 0, 0, false),
          "A running session must reject another start");
          
    std::cout << "FocusEngine boundary tests passed.\n";
    return EXIT_SUCCESS;
}