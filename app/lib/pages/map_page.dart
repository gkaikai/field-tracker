// 地图首页 - 实时定位 + 打卡 + 客户标记

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:geolocator/geolocator.dart';
import '../config/amap_key.dart';
import '../services/attendance_service.dart';
import '../services/api_service.dart';
import 'attendance_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  AMapController? _mapController;
  Position? _currentPosition;
  bool _isLocating = false;
  bool _isCheckInLoading = false;
  String _statusText = '正在获取定位...';

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
    try {
      // 检查定位权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _statusText = '定位权限被拒绝，请在设置中开启');
        }
        return;
      }

      // 获取当前位置
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLocating = true;
          _statusText = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        });
        _mapController?.moveCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusText = '定位失败: $e');
      }
    }
  }

  void _locateMe() {
    if (_currentPosition != null) {
      _mapController?.moveCamera(
        CameraUpdate.newLatLng(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude)),
      );
    } else {
      _initLocation();
    }
  }

  /// 打卡
  void _onCheckIn() async {
    final pos = _currentPosition;
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

  // -------- 客户标记相关 --------

  /// 从 API 拉取客户列表，为有坐标的客户创建地图标记
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
        // 跳过没有坐标的客户
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
          _statusText = '${_currentPosition != null ? '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}' : '定位中...'} | 客户 ${markers.length}';
        });
      }
    } catch (e) {
      debugPrint('加载客户标记失败: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  /// 点击客户标记时弹出详情面板（含拜访按钮）
  void _onCustomerMarkerTapped(Map<String, dynamic> customer) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CustomerMarkerSheet(
        customer: customer,
        currentPosition: _currentPosition,
        onVisit: _visitCustomer,
      ),
    );
  }

  /// 提交拜访记录
  Future<void> _visitCustomer(Map<String, dynamic> customer) async {
    final pos = _currentPosition;
    if (pos == null) {
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
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
      if (!mounted) return;
      Navigator.pop(context); // 关闭底部面板
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已记录对 ${customer['name']} 的拜访'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拜访记录失败: $e'), backgroundColor: Colors.red),
      );
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
              if (_currentPosition != null) {
                controller.moveCamera(
                  CameraUpdate.newLatLng(LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    // 返回按钮
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back, size: 24, color: Colors.blue),
                    ),
                    const SizedBox(width: 8),
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
                      child: Text(
                        _statusText,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ---- 底部按钮行：定位 + 打卡 + 记录 ----
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 24,
            right: 24,
            child: Row(
              children: [
                FloatingActionButton.small(
                  heroTag: 'locate',
                  onPressed: _locateMe,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(width: 16),
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
          ),
        ],
      ),
    );
  }
}

// ---- 客户标记底部面板 ----

class _CustomerMarkerSheet extends StatelessWidget {
  final Map<String, dynamic> customer;
  final Position? currentPosition;
  final Future<void> Function(Map<String, dynamic>) onVisit;

  const _CustomerMarkerSheet({
    required this.customer,
    required this.currentPosition,
    required this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    final name = customer['name'] as String? ?? '';
    final phone = customer['phone'] as String? ?? '';
    final address = customer['address'] as String? ?? '';
    final lat = (customer['lat'] as num?)?.toDouble();
    final lng = (customer['lng'] as num?)?.toDouble();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 客户名称
          Row(
            children: [
              const Icon(Icons.business, color: Colors.blue, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 电话
          if (phone.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(phone, style: const TextStyle(fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // 地址
          if (address.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(address, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // 坐标
          if (lat != null && lng != null) ...[
            Row(
              children: [
                const Icon(Icons.map, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 拜访按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: currentPosition != null
                  ? () => onVisit(customer)
                  : null,
              icon: const Icon(Icons.assignment),
              label: Text(
                currentPosition != null ? '记录拜访' : '等待定位...',
                style: const TextStyle(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
