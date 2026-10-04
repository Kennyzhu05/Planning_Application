# Android focus monitoring

Re-run CMake for the Android arm64-v8a kit, rebuild, and deploy the APK with
Qt Creator's Run button. Use the existing Android SDK 36 / build-tools 36.0.0
and matching NDK. The target includes this folder through
`QT_ANDROID_PACKAGE_SOURCE_DIR`; keep Qt's generated Gradle files and the
existing OpenSSL configuration. No backend deployment or extra npm package
is needed. The application/package identity remains Qt's existing default,
so installing the new APK with the same signing configuration updates it.

## Phone setup

1. Open DailyPlanner and choose **Start Focus** and a mode/duration.
2. On Android 13+, allow the notification permission prompt and tap Start again.
   If previously denied, use **Notification settings** in focus setup and enable
   the app plus Active focus session, One-minute focus reminders, and Five-minute
   focus warnings. Enable banners/pop-ups for the warning channel if desired.
3. If your phone restricts background apps, use **Battery settings**, find
   DailyPlanner, and allow background activity / unrestricted battery use.
   The exact labels differ by device; Oppo may have another per-app setting
   under App management > DailyPlanner > Battery usage.
4. Start focus, turn the screen off, and work on your task. The ongoing
   **Focus active** notification offers **Open planner** and **End focus**.

## Implemented behavior

- An awake/interactive screen counts even on the lock screen or in another app.
  Ambient always-on display does not count. No app-content tracking, usage-access
  permission, accessibility service, or overlay permission is used.
- At 60 continuous screen-on seconds, show a gentle notification and in-app banner.
- At 300 continuous seconds, show a stronger high-importance notification with a
  red accent and a red in-app banner. Repeat the stronger notification at each
  additional five-minute threshold (10, 15, etc.), without sending missed reminders
  in a burst if Android delays a callback.
- Screen-off clears the current reminder and resets the streak and thresholds.
  Overall focus time continues; previous screen-use totals remain counted.
  As on desktop, screen-use streaks shorter than one minute do not enter that total.
- Timed sessions accept 1 minute through 24 hours; open-ended sessions end manually.
  Ending/completing/interruption unregisters screen monitoring and clears focus
  notifications, callbacks, and the completion alarm.
- Reopening the planner reads the current service state. The Qt timer only refreshes
  the display; it does not control Android reminders. Desktop keeps FocusEngine
  and its simulated screen-state control.

## Files and lifecycle

- `AndroidManifest.xml`: Qt activity/provider template, permissions, private
  service/provider/receiver in the `:focus` process, and the special-use FGS type.
- `src/org/dailyplanner/focus/FocusService.java`: authoritative monotonic session
  clock, interactive-state receiver, notification channels, thresholds, and cleanup.
- `FocusBridge.java`: JNI methods in the Qt process, notification permission prompt,
  settings links, and IPC to the monitor.
- `FocusStateProvider.java`: unexported, same-UID IPC endpoint for starting,
  stopping, and reading the session. No planner records are exposed.
- `FocusExpiryReceiver.java`: an inexact idle alarm backstop for timed completion.
- `res/drawable/ic_focus.xml`: Android notification icon.
- `../src/focus/focuscontroller.{h,cpp}`: reads Android snapshots and exposes warning
  level, errors, and settings actions to QML; preserves desktop simulation.
- `../qml/Main.qml`: shared in-app reminder/error banner and state refresh on return.
- `../qml/dialogs/FocusSetupDialog.qml`: reminder explanation and permission/settings
  guidance in the existing duration picker.

The service runs in a separate Android process to survive destruction of the Qt
activity/native runtime. It uses elapsed realtime (including deep sleep), not wall
clock time. Only an active-session marker is persisted locally, to report a session
as interrupted if its process died; an interrupted session is never silently resumed.
Force-stop, reboot, Android's Stop action, or manufacturer process restrictions can
still end monitoring. Allowing background activity helps but cannot prevent force-stop.

Android controls notification presentation and respects channel settings and Do Not
Disturb. A heads-up pop-up, red background, sound, or vibration is not guaranteed;
the app does not forcibly cover other apps. Screen-on reminders need the monitor to
remain alive. During deep sleep the non-exact completion alarm may be delayed; elapsed
time stays capped at the chosen duration and completion is reconciled on the next
service callback/screen event. No wake lock keeps the phone awake.

Android 14+ requires the foreground service type/permission declared in the manifest.
This user-started screen-focus monitor uses `specialUse`; a future Google Play release
needs the corresponding service declaration and review.

## Manual checks for the owner

No build or device tests were run for this change, as requested. After deploying:

1. Start a session longer than five minutes; switch to another app and keep the
   screen awake. Check the one-minute reminder, five-minute warning, and red banner
   when returning to DailyPlanner. Keep it awake until ten minutes to check repetition.
2. Turn the screen off between thresholds, then back on. Confirm a fresh streak,
   cleared warnings, and a continuing overall timer. Try the lock screen too.
3. Reopen the app, and optionally remove its activity from recents. Confirm the
   same active session and notification action **End focus**.
4. Try timed completion, manual stop, open-ended mode, denied notifications, a
   disabled warning channel, and force-stop/relaunch. Confirm readable guidance
   and no stale active session. Check both short and longer screen-off sessions.

Platform references: [interactive state](https://developer.android.com/reference/android/os/PowerManager#isInteractive()),
[notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission),
[foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use),
and [idle alarms](https://developer.android.com/reference/android/app/AlarmManager#setAndAllowWhileIdle(int,%20long,%20android.app.PendingIntent)).
