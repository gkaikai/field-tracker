// 地图首页 - 实时定位显示 + 打卡入口

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/background_service.dart';
import '../services/location_uploader.dart';
import '../services/attendance_service.dart';
import '../models/location_point.dart';
import 'permission_guide_page.dart';
import 'attendance_page.dart';
import '../config/amap_key.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  AMapController? _mapController;
  bool _isLocating = false;
  bool _isCheckInLoading = false;
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
    final locService = LocationService();
    locService.onLocationChanged = null;
    locService.onError = null;
    LocationUploader().onAuthError = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _initLocation() async {
    final locService = LocationService();

    locService.onLocationChanged = (Position position) {
      if (mounted) {
        setState(() {
          _isLocating = true;
          _statusText =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
        _mapController?.moveCamera(
          CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude)),
        );
      }

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
      } catch (_) {}
    };

    locService.onError = (String msg) {
      if (mounted) {
        setState(() => _statusText = msg);
      }
    };

    LocationUploader().onAuthError = () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    };

    await locService.startTracking();
    await BackgroundService().start();
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

  /// 打卡 — 显示签到/签退选择
  void _onCheckIn() async {
    final pos = LocationService().currentPosition;
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未获取到位置，请稍后重试'), backgroundColor: Colors.orange),
      );
      return;
    }

    // 选择打卡类型
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('打卡'),
        content: const Text('请选择打卡类型：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'checkin'),
            child: const Text('签到', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'checkout'),
            child: const Text('签退', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (type == null || !mounted) return;

    setState(() => _isCheckInLoading = true);
    try {
      final result = await AttendanceService().checkin(
        type: type,
        lng: pos.longitude,
        lat: pos.latitude,
        address: '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
      );

      if (!mounted) return;

      final checkTime = result['checkTime'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${type == "checkin" ? "签到" : "签退"}成功 ($checkTime)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打卡失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCheckInLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AMapWidget(
            apiKey: const AMapApiKey(
              androidKey: AMapConfig.androidKey,
              iosKey: AMapConfig.iosKey,
            ),
            initialCameraPosition: const CameraPosition(
              target: LatLng(39.909, 116.397),
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
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isLocating ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
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
            if (_cacheCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 主按钮行：定位 + 打卡 + 记录
          Row(
            children: [
              FloatingActionButton.small(
                heroTag: 'locate',
                onPressed: _locateMe,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(width: 16),
              // 打卡按钮
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isCheckInLoading ? null : _onCheckIn,
                    icon: _isCheckInLoading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.fingerprint, size: 24),
                    label: Text(_isCheckInLoading ? '打卡中...' : '打卡', style: const TextStyle(fontSize: 16)),
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
              const SizedBox(width: 12),
              // 记录按钮
              FloatingActionButton.small(
                heroTag: 'records',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AttendancePage()),
                ),
                backgroundColor: Colors.white,
                child: const Icon(Icons.history, color: Colors.blue),
              ),
            ],
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

  void _locateMe() {
    final pos = LocationService().currentPosition;
    if (pos != null) {
      _mapController?.moveCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }
  }
}
