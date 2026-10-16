package com.haam.keepawake;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiManager;
import android.os.IBinder;
import android.os.PowerManager;

/**
 * Keeps the TV's processor and Wi-Fi awake while its screen is off.
 *
 * Without it the TV falls into deep sleep a few minutes after it is turned
 * off and drops off the Wi-Fi, so the phone can no longer reach it. With the
 * locks held the screen still goes dark, but the remote service keeps
 * answering and the phone's power button works at any time.
 */
public final class KeepAwakeService extends Service {
    /** Shown in `dumpsys power`, which the phone app uses to check the state. */
    static final String TAG = "haam:keepawake";
    private static final String CHANNEL = "keep_awake";

    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationManager notifications = getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(
                new NotificationChannel(CHANNEL, "Reachable from the phone", NotificationManager.IMPORTANCE_MIN));
        Notification notification = new Notification.Builder(this, CHANNEL)
                .setContentTitle("HAAM Remote")
                .setContentText("Keeps the TV reachable from the phone while it is off")
                .setSmallIcon(android.R.drawable.ic_lock_power_off)
                .setOngoing(true)
                .build();
        startForeground(1, notification);

        PowerManager power = getSystemService(PowerManager.class);
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG);
        wakeLock.setReferenceCounted(false);
        wakeLock.acquire();

        WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifi != null) {
            @SuppressWarnings("deprecation")
            int mode = WifiManager.WIFI_MODE_FULL_HIGH_PERF;
            wifiLock = wifi.createWifiLock(mode, TAG);
            wifiLock.setReferenceCounted(false);
            wifiLock.acquire();
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY; // restarted by the system if it is ever killed
    }

    @Override
    public void onDestroy() {
        if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
