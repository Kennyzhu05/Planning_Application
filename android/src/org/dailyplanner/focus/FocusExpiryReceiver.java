package org.dailyplanner.focus;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Inexact idle alarm to finish timed focus while the screen is off. */
public final class FocusExpiryReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        FocusService.expire(context, intent.getLongExtra("started", -1));
    }
}
