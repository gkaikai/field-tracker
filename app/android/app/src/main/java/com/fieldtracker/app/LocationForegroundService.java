package com.fieldtracker.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;

import com.amap.api.location.AMapLocation;
import com.amap.api.location.AMapLocationClient;
import com.amap.api.location.AMapLocationClientOption;
import com.amap.api.location.AMapLocationListener;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import io.flutter.plugin.common.MethodChannel;

/**
 * 原生定位前台服务 — 单AMap实例架构
 *
 * 单一高德定位客户端，同时服务两个目标：
 * 1. Flutter层（MethodChannel → 地图显示/数据处理）
 * 2. 原生HTTP上传（Flutter被冻结时的保底）
 *
 * 注意：Flutter AMap插件的定位功能已禁用，
 * 统一由此原生服务管理高德SDK实例，避免冲突。
 */
public class LocationForegroundService extends Service implements AMapLocationListener {
    private static final String TAG = "AMapLocationService";
    private static final int NOTIFICATION_ID = 888;
    private static final String CHANNEL_ID = "field_tracker_location";
    private static final int UPLOAD_INTERVAL_SEC = 12;
    private static final int MAX_BUFFER_SIZE = 5000;

    private AMapLocationClient locationClient;
    private Handler handler = new Handler(Looper.getMainLooper());
    private static MethodChannel methodChannel;
    private boolean isRunning = false;
    private PowerManager.WakeLock wakeLock;
    private ScheduledExecutorService uploadExecutor;
    private static String serverUrl = "";
    private static String authToken = "";
    private static LocationForegroundService currentInstance;
    private boolean nativeUploadEnabled = false;  // true时nativeBuffer才写入

    private final List<AMapLocation> nativeBuffer = new ArrayList<>();
    private final AtomicInteger totalNativeUploaded = new AtomicInteger(0);

    public static void setMethodChannel(MethodChannel channel) {
        methodChannel = channel;
    }

    /// 设置服务器配置（原生HTTP上传已关闭，保留供恢复时使用）
    public static void setServerConfig(String url, String token) {
        serverUrl = url;
        authToken = token;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        currentInstance = this;  // 静态引用，供setGpsInterval使用

        // 高德SDK隐私合规声明
        try {
            AMapLocationClient.updatePrivacyShow(this, true, true);
            AMapLocationClient.updatePrivacyAgree(this, true);
        } catch (Exception e) {
            Log.w(TAG, "隐私声明设置异常", e);
        }

        // 初始化高德定位客户端（此进程唯一的AMapLocationClient实例）
        try {
            locationClient = new AMapLocationClient(this);
            locationClient.setLocationListener(this);
        } catch (Exception e) {
            Log.e(TAG, "AMapLocationClient初始化失败", e);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (isRunning) return START_STICKY;

        acquireWakeLock();
        startForeground();
        startLocationUpdates();
        // 原生HTTP保底上传通道已关闭 —— 单AMap架构下Flutter通道已足够稳定
        // 两条通道同时上传会导致服务端数据重复，轨迹出现双线
        // startNativeUploadTimer();

        isRunning = true;
        Log.d(TAG, "原生定位前台服务已启动 (单一AMap实例)");
        return START_STICKY;
    }

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    TAG + ":locationLock"
                );
                wakeLock.acquire(30 * 60 * 1000L);
                Log.d(TAG, "WakeLock已获取(30min)");
            }
        } catch (Exception e) {
            Log.w(TAG, "获取WakeLock失败", e);
        }
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
        startLocationUpdatesWithInterval(3000);
    }

    private void startLocationUpdatesWithInterval(int intervalMs) {
        if (locationClient == null) return;

        AMapLocationClientOption option = new AMapLocationClientOption();
        option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Hight_Accuracy);
        option.setInterval(intervalMs);
        option.setOnceLocation(false);
        option.setNeedAddress(false);
        option.setLocationCacheEnable(false);
        option.setSensorEnable(true);

        locationClient.setLocationOption(option);
        locationClient.startLocation();
        Log.d(TAG, "GPS采集间隔已设为 " + intervalMs + "ms");
    }

    /// 公开方法：供MainActivity的MethodChannel调用，动态调整GPS采集间隔（热切换，不断流）
    public static void setGpsInterval(int intervalMs) {
        LocationForegroundService inst = currentInstance;
        if (inst == null || inst.locationClient == null) return;
        // 热切换：AMap SDK支持在运行时直接setLocationOption，无需stop+start
        try {
            AMapLocationClientOption option = new AMapLocationClientOption();
            option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Hight_Accuracy);
            option.setInterval(intervalMs);
            option.setOnceLocation(false);
            option.setNeedAddress(false);
            option.setLocationCacheEnable(false);
            option.setSensorEnable(true);
            inst.locationClient.setLocationOption(option);
            Log.d(TAG, "GPS采集间隔热切换为 " + intervalMs + "ms");
        } catch (Exception e) {
            Log.w(TAG, "GPS间隔热切换失败", e);
        }
    }

    private void startNativeUploadTimer() {
        nativeUploadEnabled = true;
        if (uploadExecutor != null && !uploadExecutor.isShutdown()) {
            uploadExecutor.shutdown();
        }
        uploadExecutor = Executors.newSingleThreadScheduledExecutor();
        uploadExecutor.scheduleAtFixedRate(
            () -> {
                try {
                    flushNativeBuffer();
                } catch (Throwable t) {
                    Log.e(TAG, "原生上传定时器异常", t);
                }
            },
            UPLOAD_INTERVAL_SEC,
            UPLOAD_INTERVAL_SEC,
            TimeUnit.SECONDS
        );
        Log.d(TAG, "原生上传定时器已启动(每" + UPLOAD_INTERVAL_SEC + "秒)");
    }

    @Override
    public void onLocationChanged(AMapLocation amapLocation) {
        if (amapLocation == null) return;

        if (amapLocation.getErrorCode() != 0) {
            Log.w(TAG, "定位失败, code=" + amapLocation.getErrorCode()
                    + ", msg=" + amapLocation.getErrorInfo());
            return;
        }

        if (amapLocation.getAccuracy() > 100) return;

        // 1) 加入原生上传缓存（关闭时跳过，避免无意义内存开销）
        if (nativeUploadEnabled) {
        synchronized (nativeBuffer) {
            if (nativeBuffer.size() < MAX_BUFFER_SIZE) {
                nativeBuffer.add(amapLocation);
            } else {
                Log.w(TAG, "原生缓存已达上限(" + MAX_BUFFER_SIZE + ")，丢弃最旧点");
                nativeBuffer.remove(0);
                nativeBuffer.add(amapLocation);
            }
        }
        }

        // 2) 通过MethodChannel发给Flutter（地图显示/数据处理）
        if (methodChannel != null) {
          handler.post(() -> {
            try {
                java.util.HashMap<String, Object> data = new java.util.HashMap<>();
                data.put("lat", amapLocation.getLatitude());
                data.put("lng", amapLocation.getLongitude());
                data.put("accuracy", (double) amapLocation.getAccuracy());
                data.put("speed", (double) amapLocation.getSpeed());
                data.put("timestamp", System.currentTimeMillis());
                methodChannel.invokeMethod("onLocationUpdate", data);
            } catch (Exception e) {
                Log.w(TAG, "MethodChannel发送失败", e);
            }
          });
        }
    }

    private void flushNativeBuffer() {
        final List<AMapLocation> batch;
        synchronized (nativeBuffer) {
            if (nativeBuffer.isEmpty()) return;
            batch = new ArrayList<>(nativeBuffer);
            nativeBuffer.clear();
        }

        if (serverUrl.isEmpty() || authToken.isEmpty()) {
            Log.d(TAG, "原生上传跳过：未配置服务器地址或Token");
            synchronized (nativeBuffer) {
                nativeBuffer.addAll(batch);
            }
            return;
        }

        HttpURLConnection conn = null;
        try {
            JSONArray points = new JSONArray();
            for (AMapLocation loc : batch) {
                JSONObject pt = new JSONObject();
                pt.put("lat", loc.getLatitude());
                pt.put("lng", loc.getLongitude());
                pt.put("accuracy", (double) loc.getAccuracy());
                pt.put("speed", (double) loc.getSpeed());
                // 使用GPS真实采集时间戳，避免与Flutter通道数据重复
                // AMapLocation.getTime()返回long（毫秒时间戳），直接用
                pt.put("timestamp", loc.getTime());
                points.put(pt);
            }

            URL url = new URL(serverUrl + "/api/v1/location/batch");
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setRequestProperty("Authorization", "Bearer " + authToken);
            conn.setDoOutput(true);
            conn.setConnectTimeout(8000);
            conn.setReadTimeout(8000);

            JSONObject body = new JSONObject();
            body.put("points", points);
            byte[] bodyBytes = body.toString().getBytes("UTF-8");

            OutputStream os = conn.getOutputStream();
            os.write(bodyBytes);
            os.flush();
            os.close();

            int code = conn.getResponseCode();

            if (code >= 200 && code < 300) {
                totalNativeUploaded.addAndGet(batch.size());
                Log.d(TAG, "原生上传成功: " + batch.size() + "点, 累计=" + totalNativeUploaded.get());
            } else {
                Log.w(TAG, "原生上传失败 HTTP " + code + ", " + batch.size() + "点保留重试");
                synchronized (nativeBuffer) {
                    nativeBuffer.addAll(batch);
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "原生上传异常", e);
            synchronized (nativeBuffer) {
                nativeBuffer.addAll(batch);
            }
        } finally {
            if (conn != null) {
                try { conn.disconnect(); } catch (Exception ignored) {}
            }
        }
    }

    /// 解析AMapLocation.getTime()的"yyyy-MM-dd HH:mm:ss"格式为毫秒时间戳
    private static long parseTimestampFromAmap(String amapTime) {
        if (amapTime == null || amapTime.isEmpty()) return System.currentTimeMillis();
        try {
            java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault());
            java.util.Date date = sdf.parse(amapTime);
            return date != null ? date.getTime() : System.currentTimeMillis();
        } catch (Exception e) {
            return System.currentTimeMillis();
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
        if (currentInstance == this) currentInstance = null;
        if (uploadExecutor != null) {
            uploadExecutor.shutdown();
            uploadExecutor = null;
        }
        if (locationClient != null) {
            locationClient.stopLocation();
            locationClient.onDestroy();
            locationClient = null;
        }
        if (wakeLock != null && wakeLock.isHeld()) {
            try {
                wakeLock.release();
            } catch (Exception ignored) {}
        }
        stopForeground(true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
