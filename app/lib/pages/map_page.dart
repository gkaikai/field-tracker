// 地图首页 - 实时定位 + 打卡 + 客户标记
// 使用高德定位SDK代替Geolocator

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:dio/dio.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/amap_key.dart';
import '../services/location_service.dart';
import '../services/attendance_service.dart';
import '../services/api_service.dart';
import '../services/error_codes.dart';
import 'attendance_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  AMapController? _mapController;
  double? _currentLat;
  double? _currentLng;
  bool _isLocating = false;
  bool _isCheckInLoading = false;
  String _statusText = '正在获取定位...';
  String _accuracyText = '';

  // 客户标记相关
  final ApiService _api = ApiService();
  Set<Marker> _customerMarkers = {};
  bool _isLoadingCustomers = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadCustomers();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initLocation() async {
    // 用LocationService替代Geolocator
    final loc = LocationService();
    if (loc.isRunning) {
      // 如果已经启动，直接取最新位置
      if (loc.currentLat != null && loc.currentLng != null) {
        if (mounted) {
          setState(() {
            _currentLat = loc.currentLat;
            _currentLng = loc.currentLng;
            _isLocating = true;
            _statusText =
                '${loc.currentLat!.toStringAsFixed(4)}, ${loc.currentLng!.toStringAsFixed(4)}';
          });
        }
      }
      return;
    }

    // 监听定位结果
    loc.onLocationChanged = (lat, lng, accuracy, speed) {
      if (mounted) {
        setState(() {
          _currentLat = lat;
          _currentLng = lng;
          _isLocating = true;
          _statusText =
              '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
          _accuracyText = '精度: ${accuracy.toStringAsFixed(0)}m'
              '${speed != null && speed > 0 ? ' 速度: ${speed.toStringAsFixed(1)}m/s' : ''}';
        });
        _mapController?.moveCamera(
          CameraUpdate.newLatLng(LatLng(lat, lng)),
        );
      }
    };

    // 启动高德定位
    final started = await loc.startTracking();
    if (!started && mounted) {
      setState(() => _statusText = '定位启动失败，请在设置中开启定位权限和GPS');
    }

    // 启动后台前台服务（息屏保活）
    try {
      final service = FlutterBackgroundService();
      // 将login token传给后台服务
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token != null) {
        service.startService();
        service.invoke('setAsForeground');
      }
    } catch (_) {}
  }

  void _locateMe() {
    final lat = _currentLat;
    final lng = _currentLng;
    if (lat != null && lng != null) {
      _mapController?.moveCamera(
        CameraUpdate.newLatLng(LatLng(lat, lng)),
      );
    } else {
      _initLocation();
    }
  }

  /// 打卡
  void _onCheckIn() async {
    final lat = _currentLat;
    final lng = _currentLng;
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('尚未获取到位置，请稍后重试'),
            backgroundColor: Colors.orange),
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
            child:
                const Text('签到', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'checkout'),
            child:
                const Text('签退', style: TextStyle(fontSize: 16)),
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
        lng: lng,
        lat: lat,
        address: '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
      );

      if (!mounted) return;

      final checkTime = result['checkTime'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${type == "checkin" ? "签到" : "签退"}成功 ($checkTime)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // 提取业务错误信息展示给用户
      String msg = '打卡失败';
      if (e is DioException && e.error is ApiException) {
        msg = (e.error as ApiException).friendlyMessage;
      } else if (e is ApiException) {
        msg = e.friendlyMessage;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCheckInLoading = false);
    }
  }

  // -------- 客户标记相关 --------

  Future<void> _loadCustomers() async {
    if (_isLoadingCustomers) return;
    setState(() => _isLoadingCustomers = true);
    try {
      final resp = await _api.get('/api/v1/customers');
      final data = resp.data as Map<String, dynamic>;
      final list = (data['customers'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final markers = <Marker>{};
      for (final c in list) {
        final lat = (c['lat'] as num?)?.toDouble();
        final lng = (c['lng'] as num?)?.toDouble();
        if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;

        final name = c['name'] as String? ?? '';
        final phone = c['phone'] as String? ?? '';

        markers.add(Marker(
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: name,
            snippet: phone.isNotEmpty ? '📞 $phone' : '暂无电话',
          ),
          onTap: (_) => _onCustomerMarkerTapped(c),
        ));
      }

      if (mounted) {
        setState(() {
          _customerMarkers = markers;
          _statusText =
              '${_currentLat != null ? '${_currentLat!.toStringAsFixed(4)}, ${_currentLng!.toStringAsFixed(4)}' : '定位中...'} | 客户 ${markers.length}';
        });
      }
    } catch (e) {
      debugPrint('加载客户标记失败: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  void _onCustomerMarkerTapped(Map<String, dynamic> customer) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CustomerMarkerSheet(
        customer: customer,
        lat: _currentLat,
        lng: _currentLng,
        onVisit: _visitCustomer,
      ),
    );
  }

  Future<void> _visitCustomer(Map<String, dynamic> customer) async {
    final lat = _currentLat;
    final lng = _currentLng;
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('尚未获取到位置，无法记录拜访'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await _api.post('/api/v1/customers/visit', data: {
        'customerId': customer['id'],
        'lat': lat,
        'lng': lng,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已记录对 ${customer['name']} 的拜访'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('拜访记录失败: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AMapWidget(
            apiKey: AMapApiKey(
              androidKey: AMapConfig.androidKey,
              iosKey: AMapConfig.iosKey,
            ),
            privacyStatement: const AMapPrivacyStatement(
              hasContains: true,
              hasShow: true,
              hasAgree: true,
            ),
            initialCameraPosition: const CameraPosition(
              target: LatLng(39.909, 116.397),
              zoom: 15,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              if (_currentLat != null && _currentLng != null) {
                controller.moveCamera(
                  CameraUpdate.newLatLng(
                      LatLng(_currentLat!, _currentLng!)),
                );
              }
            },
            myLocationStyleOptions: MyLocationStyleOptions(true),
            compassEnabled: true,
            scaleEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            markers: _customerMarkers,
          ),

          // ---- 顶部状态栏 ----
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _currentLat != null
                          ? Icons.location_on
                          : Icons.location_searching,
                      color: _currentLat != null
                          ? Colors.green
                          : Colors.grey,
                      size: 18,
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
                          if (_accuracyText.isNotEmpty)
                            Text(
                              _accuracyText,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ---- 底部操作按钮 ----
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // 定位我
                FloatingActionButton.small(
                  heroTag: 'locate',
                  onPressed: _locateMe,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location,
                      color: Colors.blue),
                ),
                const SizedBox(width: 12),
                // 查看轨迹
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AttendancePage()),
                    ),
                    icon: const Icon(Icons.timeline),
                    label: const Text('考勤轨迹'),
                  ),
                ),
                const SizedBox(width: 12),
                // 打卡
                ElevatedButton.icon(
                  onPressed: _isCheckInLoading ? null : _onCheckIn,
                  icon: _isCheckInLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(_isCheckInLoading ? '打卡中...' : '打卡'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 客户标记底部面板 ----
class _CustomerMarkerSheet extends StatelessWidget {
  final Map<String, dynamic> customer;
  final double? lat;
  final double? lng;
  final void Function(Map<String, dynamic> customer) onVisit;

  const _CustomerMarkerSheet({
    required this.customer,
    required this.lat,
    required this.lng,
    required this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    final name = customer['name'] as String? ?? '';
    final phone = customer['phone'] as String? ?? '';
    final address = customer['address'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (phone.isNotEmpty)
            Text('📞 $phone',
                style: const TextStyle(color: Colors.grey)),
          if (address.isNotEmpty)
            Text('📍 $address',
                style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: lat != null
                  ? () => onVisit(customer)
                  : null,
              icon: const Icon(Icons.how_to_reg),
              label: Text(
                  lat != null ? '记录拜访' : '等待定位...'),
            ),
          ),
        ],
      ),
    );
  }
}
