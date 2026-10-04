package org.dailyplanner.focus;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import org.json.JSONObject;

/** Android owns the focus clock; Qt only reads snapshots of this service. */
public final class FocusService extends Service {
    private static final Object LOCK = new Object();
    private static final String ACTIVE_CHANNEL = "focus_active_v1";
    private static final String GENTLE_CHANNEL = "focus_gentle_v1";
    private static final String RED_CHANNEL = "focus_warning_v1";
    private static final String STOP = "org.dailyplanner.focus.STOP";
    private static final int ACTIVE_ID = 4101;
    private static final int REMINDER_ID = 4102;
    private static final long MINUTE = 60000;
    private static final long RED_INTERVAL = 5 * MINUTE;
    private static FocusService instance;
    private static boolean initialized;
    private static String status = "Idle", error = "";
    private static long planned, started, elapsed, unlockStarted, finishedUse, use, streak;
    private static long pendingAt, nextRed = RED_INTERVAL;
    private static boolean interactive, gentleShown;
    private static int warning;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean receiverRegistered;

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences("focus_monitor", MODE_PRIVATE);
    }

    private static void initialize(Context context) {
        if (initialized) return;
        initialized = true;
        // A killed process/reboot cannot reconstruct missed screen events honestly.
        if (preferences(context).getBoolean("active", false)) {
            status = "Interrupted";
            error = "Android stopped the previous focus session. Allow background activity in battery settings, then start a new session.";
            preferences(context).edit().putBoolean("active", false).apply();
            context.getSystemService(NotificationManager.class).cancel(ACTIVE_ID);
            context.getSystemService(NotificationManager.class).cancel(REMINDER_ID);
        }
    }

    static void createChannels(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel(ACTIVE_CHANNEL,
                "Active focus session", NotificationManager.IMPORTANCE_LOW));
        NotificationChannel gentle = new NotificationChannel(GENTLE_CHANNEL,
                "One-minute focus reminders", NotificationManager.IMPORTANCE_DEFAULT);
        gentle.setDescription("A reminder after one continuous minute with the screen awake.");
        manager.createNotificationChannel(gentle);
        NotificationChannel red = new NotificationChannel(RED_CHANNEL,
                "Five-minute focus warnings", NotificationManager.IMPORTANCE_HIGH);
        red.setDescription("A stronger reminder after five minutes, then every five minutes.");
        red.enableVibration(true);
        manager.createNotificationChannel(red);
    }

    static boolean notificationsAllowed(Context context) {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            return false;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (!manager.areNotificationsEnabled()) return false;
        for (String id : new String[]{ACTIVE_CHANNEL, GENTLE_CHANNEL, RED_CHANNEL}) {
            NotificationChannel channel = manager.getNotificationChannel(id);
            if (channel != null && channel.getImportance() == NotificationManager.IMPORTANCE_NONE)
                return false;
        }
        return true;
    }

    /** Empty string means accepted; startup failures are returned in the snapshot. */
    static String prepareStart(Context context, long duration) {
        synchronized (LOCK) {
            initialize(context);
            if (duration != 0 && (duration < MINUTE || duration > 24 * 60 * MINUTE))
                return error = "Choose a duration from 1 minute to 24 hours.";
            if (status.equals("Running") || status.equals("Starting"))
                return error = "A focus session is already active.";
            if (instance != null)
                return error = "The previous session is ending. Try again in a moment.";
            try {
                createChannels(context);
                if (!notificationsAllowed(context))
                    return error = "Enable DailyPlanner notifications and all three focus notification categories in notification settings, then try again.";
                error = "";
                planned = duration;
                elapsed = use = streak = 0;
                warning = 0;
                interactive = false;
                pendingAt = SystemClock.elapsedRealtime();
                status = "Starting";
                return "";
            } catch (RuntimeException exception) {
                status = "Interrupted";
                return error = "Android could not start background monitoring. Keep DailyPlanner open and check background activity settings.";
            }
        }
    }

    static void failStart(String message) {
        synchronized (LOCK) {
            if (status.equals("Starting")) {
                status = "Interrupted";
                error = message;
            }
        }
    }

    public static String snapshot(Context context) {
        synchronized (LOCK) {
            initialize(context);
            if (status.equals("Starting") && SystemClock.elapsedRealtime() - pendingAt > 10000) {
                status = "Interrupted";
                error = "Background monitoring did not start. Check battery settings and try again.";
            }
            JSONObject value = new JSONObject();
            try {
                value.put("status", status);
                value.put("plannedMs", planned);
                value.put("elapsedMs", elapsed);
                value.put("phoneUseMs", use);
                value.put("currentUnlockMs", streak);
                value.put("phoneInUse", interactive);
                value.put("warning", warning);
                value.put("error", error);
                value.put("notificationsAllowed", notificationsAllowed(context));
            } catch (org.json.JSONException impossible) {
                return "{}";
            }
            return value.toString();
        }
    }

    public static void requestStop(Context context) {
        synchronized (LOCK) {
            if (instance != null) {
                instance.handler.post(() -> {
                    synchronized (LOCK) { if (instance != null) instance.finish("Stopped", ""); }
                });
            } else if (status.equals("Starting")) {
                status = "Stopped";
                context.stopService(new Intent(context, FocusService.class));
            }
        }
    }

    @Override public void onCreate() {
        super.onCreate();
        synchronized (LOCK) { instance = this; }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        synchronized (LOCK) {
            if (intent == null || STOP.equals(intent.getAction())) {
                finish("Stopped", "");
                return START_NOT_STICKY;
            }
            if (status.equals("Running")) return START_NOT_STICKY;
            // Cancelled/timed-out starts must not resurrect a session.
            if (!status.equals("Starting")) { stopSelf(); return START_NOT_STICKY; }
            try {
                createChannels(this);
                Notification notification = activeNotification();
                if (Build.VERSION.SDK_INT >= 34)
                    startForeground(ACTIVE_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
                else startForeground(ACTIVE_ID, notification);
                planned = intent.getLongExtra("duration", 0);
                started = SystemClock.elapsedRealtime();
                unlockStarted = started;
                elapsed = finishedUse = use = streak = 0;
                warning = 0;
                gentleShown = false;
                nextRed = RED_INTERVAL;
                interactive = getSystemService(PowerManager.class).isInteractive();
                status = "Running";
                error = "";
                // Persist only the interruption marker, not any planner/task data.
                if (!preferences(this).edit().putBoolean("active", true).commit()) {
                    finish("Interrupted", "Could not save the focus session state. Check available device storage and try again.");
                    return START_NOT_STICKY;
                }
                IntentFilter filter = new IntentFilter();
                filter.addAction(Intent.ACTION_SCREEN_ON);
                filter.addAction(Intent.ACTION_SCREEN_OFF);
                if (Build.VERSION.SDK_INT >= 33)
                    registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
                else registerReceiver(screenReceiver, filter);
                receiverRegistered = true;
                if (planned > 0) {
                    // Inexact idle alarm is a completion backstop, not a screen-use timer.
                    getSystemService(AlarmManager.class).setAndAllowWhileIdle(
                            AlarmManager.ELAPSED_REALTIME_WAKEUP, started + planned, expiryIntent());
                }
                handler.post(ticker);
            } catch (RuntimeException exception) {
                finish("Interrupted", "Android could not enable focus monitoring. Check notification and background activity settings.");
            }
            return START_NOT_STICKY;
        }
    }

    private final BroadcastReceiver screenReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            synchronized (LOCK) {
                if (!status.equals("Running")) return;
                boolean awake = getSystemService(PowerManager.class).isInteractive();
                // Account for the previous streak without a reminder at the off boundary.
                advance(false);
                if (!status.equals("Running") || awake == interactive) return;
                finishedUse = use;
                interactive = awake;
                unlockStarted = SystemClock.elapsedRealtime();
                streak = 0;
                warning = 0;
                gentleShown = false;
                nextRed = RED_INTERVAL;
                getSystemService(NotificationManager.class).cancel(REMINDER_ID);
                handler.removeCallbacks(ticker);
                handler.post(ticker);
            }
        }
    };

    private final Runnable ticker = new Runnable() {
        @Override public void run() {
            synchronized (LOCK) {
                if (!status.equals("Running")) return;
                try {
                    if (!notificationsAllowed(FocusService.this)) {
                        finish("Interrupted", "Focus ended because notifications were disabled. Enable notifications before starting again.");
                        return;
                    }
                    advance(true);
                } catch (RuntimeException exception) {
                    finish("Interrupted", "Android could not deliver focus reminders. Check notification settings and try again.");
                }
                if (status.equals("Running")) handler.postDelayed(this, 1000);
            }
        }
    };

    private void advance(boolean reminders) {
        if (!status.equals("Running")) return;
        long now = SystemClock.elapsedRealtime();
        elapsed = Math.max(0, now - started);
        if (planned > 0) elapsed = Math.min(elapsed, planned);
        streak = interactive ? Math.max(0, started + elapsed - unlockStarted) : 0;
        use = finishedUse + (streak >= MINUTE ? streak : 0);
        if (planned > 0 && elapsed >= planned) { finish("Completed", ""); return; }
        if (!reminders || !interactive) return;
        if (streak >= nextRed) {
            gentleShown = true;
            nextRed = (streak / RED_INTERVAL + 1) * RED_INTERVAL;
            warning = 2;
            showReminder(true);
        } else if (!gentleShown && streak >= MINUTE) {
            gentleShown = true;
            warning = 1;
            showReminder(false);
        }
    }

    private PendingIntent openPlanner() {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(this, 4100, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private PendingIntent stopIntent() {
        return PendingIntent.getService(this, 4101, new Intent(this, FocusService.class).setAction(STOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private PendingIntent expiryIntent() {
        return PendingIntent.getBroadcast(this, 4103, new Intent(this, FocusExpiryReceiver.class)
                .putExtra("started", started), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private Notification activeNotification() {
        String message = planned > 0 ? "Focus for " + planned / MINUTE + " minutes. Turn off your screen."
                : "Open-ended focus. Turn off your screen when ready.";
        return new Notification.Builder(this, ACTIVE_CHANNEL)
                .setSmallIcon(getResources().getIdentifier("ic_focus", "drawable", getPackageName()))
                .setContentTitle("Focus active").setContentText(message)
                .setContentIntent(openPlanner()).setOngoing(true).setOnlyAlertOnce(true)
                .addAction(new Notification.Action.Builder(null, "Open planner", openPlanner()).build())
                .addAction(new Notification.Action.Builder(null, "End focus", stopIntent()).build())
                .build();
    }

    private void showReminder(boolean red) {
        String title = red ? "Return to your focus" : "A gentle focus reminder";
        String message = red ? "Your screen has been awake for " + streak / MINUTE
                + " minutes. Put your phone down and return to your task."
                : "Your screen has been awake for a minute. Turn it off when you're ready to focus.";
        Notification notification = new Notification.Builder(this, red ? RED_CHANNEL : GENTLE_CHANNEL)
                .setSmallIcon(getResources().getIdentifier("ic_focus", "drawable", getPackageName()))
                .setContentTitle(title).setContentText(message)
                .setStyle(new Notification.BigTextStyle().bigText(message))
                .setColor(red ? Color.rgb(239, 68, 68) : Color.rgb(129, 140, 248))
                .setCategory(Notification.CATEGORY_REMINDER).setContentIntent(openPlanner())
                .setAutoCancel(true).setTimeoutAfter(RED_INTERVAL)
                .addAction(new Notification.Action.Builder(null, "End focus", stopIntent()).build())
                .build();
        getSystemService(NotificationManager.class).notify(REMINDER_ID, notification);
    }

    private void finish(String reason, String message) {
        if (status.equals("Running")) {
            // stop/interrupt account for the final interval but do not issue reminders.
            long duration = Math.max(0, SystemClock.elapsedRealtime() - started);
            elapsed = planned > 0 ? Math.min(duration, planned) : duration;
            long current = interactive ? Math.max(0, started + elapsed - unlockStarted) : 0;
            use = finishedUse + (current >= MINUTE ? current : 0);
            if (planned > 0 && elapsed >= planned && reason.equals("Stopped")) reason = "Completed";
        }
        status = reason;
        error = message;
        interactive = false;
        streak = 0;
        warning = 0;
        handler.removeCallbacks(ticker);
        if (receiverRegistered) { unregisterReceiver(screenReceiver); receiverRegistered = false; }
        getSystemService(AlarmManager.class).cancel(expiryIntent());
        preferences(this).edit().putBoolean("active", false).apply();
        getSystemService(NotificationManager.class).cancel(REMINDER_ID);
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    static void expire(Context context, long sessionStart) {
        synchronized (LOCK) {
            if (instance != null && status.equals("Running") && started == sessionStart)
                instance.advance(false);
            else if (instance == null) initialize(context);
        }
    }

    @Override public void onDestroy() {
        synchronized (LOCK) {
            if (status.equals("Running") || status.equals("Starting"))
                finish("Interrupted", "Android stopped focus monitoring. Allow background activity in battery settings and start again.");
            handler.removeCallbacksAndMessages(null);
            if (instance == this) instance = null;
        }
        super.onDestroy();
    }

    // Swiping the planner from recents leaves a user-started service running.
    // Force-stop/reboot ends it; START_NOT_STICKY prevents silent resurrection.
    @Override public IBinder onBind(Intent intent) { return null; }
}
