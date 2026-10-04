package org.dailyplanner.focus;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;

/** JNI entry point in the Qt process. Session state lives in the :focus process. */
public final class FocusBridge {
    private FocusBridge() {}

    private static Bundle call(Context context, String method, Bundle extras) {
        Uri uri = Uri.parse("content://" + context.getPackageName() + ".focus");
        Bundle result = context.getContentResolver().call(uri, method, null, extras);
        if (result == null) throw new IllegalStateException("Focus monitor unavailable");
        return result;
    }

    public static String requestStart(Context context, long duration) {
        if (!(context instanceof Activity)) return "Open DailyPlanner before starting focus.";
        try {
            FocusService.createChannels(context);
            if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                    Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                Activity activity = (Activity) context;
                activity.runOnUiThread(() -> activity.requestPermissions(
                        new String[]{Manifest.permission.POST_NOTIFICATIONS}, 4100));
                return "Allow notifications in the permission prompt, then tap Start again. If blocked, open notification settings.";
            }
            if (!FocusService.notificationsAllowed(context))
                return "Enable DailyPlanner notifications and all three focus notification categories in notification settings, then try again.";
            Bundle extras = new Bundle();
            extras.putLong("duration", duration);
            String error = call(context, "prepare", extras).getString("error", "");
            if (!error.isEmpty()) return error;
            try {
                // Start from the visible activity's process, satisfying FGS start restrictions.
                context.startForegroundService(new Intent(context, FocusService.class)
                        .putExtra("duration", duration));
            } catch (RuntimeException exception) {
                call(context, "failStart", null);
                return "Android could not start background monitoring. Keep DailyPlanner open and check background activity settings.";
            }
            return "";
        } catch (RuntimeException exception) {
            return "Could not connect to Android focus monitoring. Rebuild the app and check background activity settings.";
        }
    }

    public static String snapshot(Context context) {
        try {
            return call(context, "snapshot", null).getString("snapshot", "{}");
        } catch (RuntimeException exception) {
            return "{\"status\":\"Interrupted\",\"error\":\"Could not connect to Android focus monitoring. Open battery settings to allow background activity, then start again.\",\"notificationsAllowed\":false}";
        }
    }

    public static void requestStop(Context context) {
        try { call(context, "stop", null); }
        catch (RuntimeException ignored) { context.stopService(new Intent(context, FocusService.class)); }
    }

    public static void openNotificationSettings(Context context) {
        openSettings(context, new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.getPackageName()));
    }

    public static void openBatterySettings(Context context) {
        openSettings(context, new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
    }

    private static void openSettings(Context context, Intent intent) {
        try { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); }
        catch (RuntimeException unavailable) {
            try {
                context.startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + context.getPackageName())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } catch (RuntimeException ignored) { /* Manufacturer has no matching settings activity. */ }
        }
    }
}
