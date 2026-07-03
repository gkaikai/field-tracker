// 地图首页 - 实时定位显示 + 打卡入口
//
// 本期功能：
//   - 高德地图加载
//   - 显示当前位置（蓝点）
//   - 显示定位状态
//   - 打卡按钮（入口，打卡逻辑放到第二期）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/background_service.dart';
import '../services/location_uploader.dart';
import '../models/location_point.dart';
import 'permission_guide_page.dart';
import '../config/amap_key.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  AMapController? _mapController;
  bool _isLocating = false;
  String _statusText = '定位初始化中...';
  String _modeText = '省电';
  int _cacheCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 清除回调以避免内存泄漏
    final locService = LocationService();
    locService.onLocationChanged = null;
    locService.onError = null;
    // 清除上传器回调，避免 AuthError 引用已销毁的 context
    LocationUploader().onAuthError = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台回到前台时刷新状态
      _refreshStatus();
    }
  }

  Future<void> _initLocation() async {
    final locService = LocationService();

    // 监听定位数据 - 使用 onLocationChanged 回调
    locService.onLocationChanged = (Position position) {
      if (mounted) {
        setState(() {
          _isLocating = true;
          _statusText =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
        // 移动地图到当前位置
        _mapController?.moveCamera(
          CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude)),
        );
      }

      // 加入上传队列（异常保护）
      try {
        LocationUploader().enqueue(
          LocationPoint(
            userId: 'current',
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            speed: position.speed,
            timestamp: position.timestamp,
          ),
        );
      } catch (_) {
        // 队列写入失败不影响定位
      }
    };

    // 监听定位错误
    locService.onError = (String msg) {
      if (mounted) {
        setState(() => _statusText = msg);
      }
    };

    // 监听认证失效（Token过期时跳回登录页）
    LocationUploader().onAuthError = () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    };

    // 启动定位
    await locService.startTracking();

    // 启动后台服务
    await BackgroundService().start();

    // 定时刷新缓存计数
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final count = await LocationUploader().getCacheCount();
    if (mounted) {
      setState(() {
        _cacheCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ---- 地图 ----
          AMapWidget(
            apiKey: const AMapApiKey(
              androidKey: AMapConfig.androidKey,
              iosKey: AMapConfig.iosKey,
            ),
            initialCameraPosition: const CameraPosition(
              target: LatLng(39.909, 116.397), // 默认天安门
              zoom: 15,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationStyleOptions: MyLocationStyleOptions(true),
            compassEnabled: true,
            scaleEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
          ),

          // ---- 顶部状态栏 ----
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _buildStatusBar(),
          ),

          // ---- 底部按钮 ----
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),

          // ---- 右上角设置入口 ----
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            right: 12,
            child: _buildSettingsButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 定位状态图标
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isLocating ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            // 定位信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusText,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '模式: $_modeText',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            // 缓存待上传数量
            if (_cacheCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '缓存$_cacheCount',
                  style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // 回到当前位置
          FloatingActionButton.small(
            heroTag: 'locate',
            onPressed: _locateMe,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(width: 16),
          // 打卡按钮（入口，功能下一期实现）
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _onCheckIn,
                icon: const Icon(Icons.fingerprint, size: 24),
                label: const Text('打卡', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsButton() {
    return FloatingActionButton.small(
      heroTag: 'settings',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PermissionGuidePage()),
      ),
      backgroundColor: Colors.white,
      child: const Icon(Icons.settings, color: Colors.grey),
    );
  }

  /// 定位到我的位置
  void _locateMe() {
    final pos = LocationService().currentPosition;
    if (pos != null) {
      _mapController?.moveCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }
  }

  /// 打卡按钮点击（第二期实现完整流程）
  void _onCheckIn() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('打卡功能将在下一期实现')),
    );
  }
}
