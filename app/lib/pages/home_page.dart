import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:amap_flutter_location/amap_flutter_location.dart';
import '../config/app_config.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';

/// 首页 - 高德地图 + 实时定位
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LocationService _locationService = LocationService();
  final AuthService _authService = AuthService();
  final AMapFlutterLocation _amapLocation = AMapFlutterLocation();

  AMapController? _mapController;
  Set<Marker> _markers = {};
  bool _isTracking = false;
  String _statusText = '未定位';

  @override
  void initState() {
    super.initState();
    _initLocationListener();
  }

  void _initLocationListener() {
    _locationService.onLocationChanged = (position) {
      setState(() {
        _statusText =
            '纬度: ${position.latitude.toStringAsFixed(6)}, 经度: ${position.longitude.toStringAsFixed(6)}';
      });
      _updateMarker(position.latitude, position.longitude);
      _animateToPosition(position.latitude, position.longitude);
    };
    _locationService.onError = (error) {
      setState(() => _statusText = '定位错误: $error');
    };
  }

  void _updateMarker(double lat, double lng) {
    setState(() {
      _markers = {
        Marker(
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      };
    });
  }

  void _animateToPosition(double lat, double lng) {
    _mapController?.moveCamera(CameraUpdate.newLatLngZoom(
      LatLng(lat, lng),
      16,
    ), animated: true);
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      _locationService.stopTracking();
      setState(() {
        _isTracking = false;
        _statusText = '定位已停止';
      });
    } else {
      final ok = await _locationService.startTracking();
      if (ok) {
        setState(() => _isTracking = true);
      }
    }
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    _amapLocation.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('外勤定位'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              _locationService.stopTracking();
              await _authService.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 高德地图
          AMapWidget(
            apiKey: AMapApiKey(androidKey: AppConfig.amapApiKey, iosKey: AppConfig.amapApiKey),
            initialCameraPosition: CameraPosition(
              target: LatLng(39.909187, 116.397451), // 北京天安门
              zoom: 14,
            ),
            markers: _markers,
            myLocationStyleOptions: MyLocationStyleOptions(true),
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),

          // 底部状态面板
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isTracking
                              ? Icons.gps_fixed
                              : Icons.gps_off,
                          color: _isTracking ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusText,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _toggleTracking,
                        icon: Icon(_isTracking
                            ? Icons.stop
                            : Icons.play_arrow),
                        label: Text(_isTracking ? '停止定位' : '开始定位'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTracking
                              ? Colors.red
                              : Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
