package com.fieldtracker.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.fieldtracker/location_service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        // 将 MethodChannel 传递给原生 ForegroundService，使其能发送定位数据回 Flutter
        LocationForegroundService.setMethodChannel(channel)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, LocationForegroundService::class.java)
                    startForegroundService(intent)
                    result.success(true)
                }
                "stopService" -> {
                    val intent = Intent(this, LocationForegroundService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "setServerConfig" -> {
                    val url = call.argument<String>("url") ?: ""
                    val token = call.argument<String>("token") ?: ""
                    LocationForegroundService.setServerConfig(url, token)
                    result.success(true)
                }
                "setGpsInterval" -> {
                    val intervalMs = call.argument<Int>("intervalMs") ?: 3000
                    LocationForegroundService.setGpsInterval(intervalMs)
                    result.success(true)
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(
                            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                        ).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_FAILED", e.message, null)
                    }
                }
                "openBatteryOptimization" -> {
                    try {
                        val intent = Intent(
                            android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        ).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
