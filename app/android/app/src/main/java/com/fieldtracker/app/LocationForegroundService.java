package com.fieldtracker.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.location.Location;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;

import io.flutter.plugin.common.MethodChannel;

public class LocationForegroundService extends Service {
    private static final String TAG = "LocationService";
    private static final int NOTIFICATION_ID = 888;
    private static final String CHANNEL_ID = "field_tracker_location";

    private FusedLocationProviderClient fusedLocationClient;
    private LocationCallback locationCallback;
    private Handler handler = new Handler(Looper.getMainLooper());
    private static MethodChannel methodChannel;
    private boolean isRunning = false;

    public static void setMethodChannel(MethodChannel channel) {
        methodChannel = channel;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this);

        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(@NonNull LocationResult locationResult) {
                for (Location location : locationResult.getLocations()) {
                    if (location == null) continue;
                    if (location.getAccuracy() > 100) continue;

                    // 每12秒一次，通过MethodChannel发送给Flutter
                    if (methodChannel != null) {
                        try {
                            methodChannel.invokeMethod("onLocationUpdate", new java.util.HashMap<String, Object>() {{
                                put("lat", location.getLatitude());
                                put("lng", location.getLongitude());
                                put("accuracy", (double) location.getAccuracy());
                                put("speed", (double) location.getSpeed());
                                put("timestamp", System.currentTimeMillis());
                            }});
                        } catch (Exception e) {
                            Log.w(TAG, "Send location failed: " + e.getMessage());
                        }
                    }
                }
            }
        };
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (isRunning) return START_STICKY;

        startForeground();
        startLocationUpdates();
        isRunning = true;
        Log.d(TAG, "定位前台服务已启动");
        return START_STICKY;
    }

    private void startForeground() {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this, 0, notificationIntent,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                        ? PendingIntent.FLAG_IMMUTABLE : 0
        );

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("外勤定位运行中")
                .setContentText("正在采集轨迹数据...")
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build();

        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
    }

    private void startLocationUpdates() {
        LocationRequest locationRequest = new LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY, 12000)  // 12秒间隔
                .setMinUpdateIntervalMillis(5000)
                .build();

        try {
            fusedLocationClient.requestLocationUpdates(
                    locationRequest, locationCallback, Looper.getMainLooper());
        } catch (SecurityException e) {
            Log.e(TAG, "定位权限不足: " + e.getMessage());
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "定位服务", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("后台定位追踪通知");
            NotificationManager manager = getSystemService(NotificationManager.class);
            manager.createNotificationChannel(channel);
        }
    }

    @Override
    public void onDestroy() {
        isRunning = false;
        if (fusedLocationClient != null && locationCallback != null) {
            fusedLocationClient.removeLocationUpdates(locationCallback);
        }
        stopForeground(true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
