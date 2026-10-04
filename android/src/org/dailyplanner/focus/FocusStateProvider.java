package org.dailyplanner.focus;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;

/** Private, same-UID IPC endpoint; no planner data is stored or exposed here. */
public final class FocusStateProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }

    @Override public Bundle call(String method, String arg, Bundle extras) {
        Bundle result = new Bundle();
        switch (method) {
            case "prepare":
                result.putString("error", FocusService.prepareStart(getContext(),
                        extras == null ? -1 : extras.getLong("duration", -1)));
                break;
            case "snapshot": result.putString("snapshot", FocusService.snapshot(getContext())); break;
            case "stop": FocusService.requestStop(getContext()); break;
            case "failStart": FocusService.failStart(
                    "Android could not start background monitoring. Keep DailyPlanner open and check background activity settings."); break;
            default: throw new IllegalArgumentException("Unknown focus operation");
        }
        return result;
    }

    @Override public String getType(Uri uri) { return null; }
    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] args, String order) { throw new UnsupportedOperationException(); }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection,
            String[] args) { throw new UnsupportedOperationException(); }
}
