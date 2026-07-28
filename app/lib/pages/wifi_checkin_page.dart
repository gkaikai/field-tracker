import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// WiFi打卡 - 快速工具类
class WifiCheckinService {
  static Future<String?> scanAndCheckin(String token) async {
    // 在真实手机上，这里会调用 wifi_iot 插件扫描附近WiFi
    // 然后在服务端匹配打卡规则中的WiFi列表
    // 由于无插件支持，这里返回占位提示
    return 'SIMULATED_WIFI';
  }
  
  /// 根据WiFi名称向服务器打卡
  static Future<bool> checkinByWifi(String token, String ssid, String bssid) async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      await dio.post('/api/v1/attendance/checkin', data: {
        'type': 'checkin',
        'lng': 0, 'lat': 0,
        'wifi_bssid': bssid,
      }, options: Options(headers: {'Authorization': 'Bearer $token'}));
      return true;
    } catch (_) { return false; }
  }
}

/// WiFi打卡页面
class WifiCheckinPage extends StatelessWidget {
  final String token;
  const WifiCheckinPage({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi打卡'), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              const Text('WiFi打卡', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('点击下方按钮扫描当前连接的WiFi\n并自动完成签到', style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('扫描WiFi并打卡', style: TextStyle(fontSize: 16)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('WiFi打卡需要真机硬件支持，请在手机上使用地图页面打卡')),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text('提示: 需要安装 wifi_iot 插件\n当前版本暂不支持模拟器', style: TextStyle(fontSize: 12, color: Colors.grey[400]), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
