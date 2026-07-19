// 轨迹回放页面 - 地图版（适配 amap_flutter_map 3.0.0 API）

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../config/amap_key.dart';

class TrackReplayPage extends StatefulWidget {
  const TrackReplayPage({super.key});

  @override
  State<TrackReplayPage> createState() => _TrackReplayPageState();
}

class _TrackReplayPageState extends State<TrackReplayPage> {
  final ApiService _api = ApiService();

  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _points = [];
  bool _isLoading = false;
  String? _error;
  double _sliderValue = 0;

  AMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  // 轨迹统计
  double _totalDistanceKm = 0;
  /// 轨迹点列表展开/收起
  bool _showPointList = false;
  final _pointListScrollController = ScrollController();
  int _hoveredPointIndex = -1;
  double _avgSpeedKmh = 0;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadTrack();
  }

  Future<void> _loadTrack() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _sliderValue = 0;
    });

    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final auth = AuthService();
      final userId = auth.userId ?? 'me';
      final resp = await _api
          .get('/api/v1/location/track/$userId', query: {'date': dateStr});
      final data = resp.data as Map<String, dynamic>;
      final points =
          (data['points'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];

      setState(() {
        _points = points;
        _isLoading = false;
      });

      _updateMap();
    } catch (e) {
      setState(() {
        _error = '加载轨迹失败: $e';
        _isLoading = false;
      });
    }
  }

  /// Haversine 公式计算两点间距离（米）
  double _haversineDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000; // 地球平均半径（米）
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double deg) => deg * math.pi / 180;

  /// 获取两点间的速度（km/h）。
  /// 优先使用数据中的 speed 字段（m/s → km/h），否则用 Haversine 距离 / 时间差计算
  double _getSegmentSpeed(Map<String, dynamic> p1, Map<String, dynamic> p2) {
    // 优先取 speed 字段
    final speedVal = (p1['speed'] ?? p2['speed']);
    if (speedVal != null && speedVal is num && speedVal > 0) {
      return speedVal.toDouble() * 3.6; // m/s → km/h
    }

    // 回退：Haversine 距离 / 时间差
    final lat1 = p1['lat'] as double;
    final lng1 = p1['lng'] as double;
    final lat2 = p2['lat'] as double;
    final lng2 = p2['lng'] as double;
    final distM = _haversineDistance(lat1, lng1, lat2, lng2);
    final t1 = DateTime.fromMillisecondsSinceEpoch(p1['timestamp'] as int);
    final t2 = DateTime.fromMillisecondsSinceEpoch(p2['timestamp'] as int);
    final dtHours = t2.difference(t1).inMilliseconds / 3600000.0;

    if (dtHours <= 0) return 0;
    return (distM / 1000.0) / dtHours; // km/h
  }

  /// 根据速度（km/h）返回轨迹段颜色
  ///  < 1 km/h → 绿,  1~5 → 黄,  5~20 → 橙,  > 20 → 红
  Color _speedColor(double speedKmh) {
    if (speedKmh < 1) return const Color(0xFF4CAF50).withOpacity(0.7); // 绿
    if (speedKmh < 5) return const Color(0xFFFFEB3B).withOpacity(0.7); // 黄
    if (speedKmh < 20) return const Color(0xFFFF9800).withOpacity(0.7); // 橙
    return const Color(0xFFF44336).withOpacity(0.7); // 红
  }

  void _updateMap() {
    if (_points.isEmpty) return;

    final polylines = <Polyline>{};
    double totalDistKm = 0;
    int totalDurationMs = 0;

    if (_points.length > 1) {
      for (int i = 0; i < _points.length - 1; i++) {
        final p1 = _points[i];
        final p2 = _points[i + 1];

        final lat1 = p1['lat'] as double;
        final lng1 = p1['lng'] as double;
        final lat2 = p2['lat'] as double;
        final lng2 = p2['lng'] as double;

        // 累计距离
        totalDistKm += _haversineDistance(lat1, lng1, lat2, lng2) / 1000.0;

        // 速度颜色
        final speedKmh = _getSegmentSpeed(p1, p2);

        polylines.add(Polyline(
          points: [LatLng(lat1, lng1), LatLng(lat2, lng2)],
          color: _speedColor(speedKmh),
          width: 6,
        ));
      }

      // 总时间
      final t1 = _points.first['timestamp'] as int;
      final t2 = _points.last['timestamp'] as int;
      totalDurationMs = (t2 - t1).abs();
    } else {
      // 单点：直接画一个点迹
      final p = _points.first;
      polylines.add(Polyline(
        points: [LatLng(p['lat'] as double, p['lng'] as double)],
        color: const Color(0xFF4CAF50).withOpacity(0.7),
        width: 6,
      ));
    }

    // 起点终点标记
    final markers = <Marker>{};
    if (_points.isNotEmpty) {
      final first = _points.first;
      final last = _points.last;

      markers.add(Marker(
        position: LatLng(first['lat'] as double, first['lng'] as double),
        icon: BitmapDescriptor.defaultMarker,
        infoWindow: const InfoWindow(title: '起点'),
      ));

      if (_points.length > 1) {
        markers.add(Marker(
          position: LatLng(last['lat'] as double, last['lng'] as double),
          icon: BitmapDescriptor.defaultMarker,
          infoWindow: const InfoWindow(title: '终点'),
        ));
      }
    }

    setState(() {
      _polylines = polylines;
      _markers = markers;
      _totalDistanceKm = totalDistKm;
      _totalDuration = Duration(milliseconds: totalDurationMs);
      _avgSpeedKmh = totalDurationMs > 0
          ? (totalDistKm / (totalDurationMs / 3600000.0))
          : 0;
    });

    _fitMapToTrack(
      _points
          .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
          .toList(),
    );
  }

  void _fitMapToTrack(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latPad = ((maxLat - minLat) * 0.3).clamp(0.001, 0.1);
    final lngPad = ((maxLng - minLng) * 0.3).clamp(0.001, 0.1);

    _mapController?.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - latPad, minLng - lngPad),
          northeast: LatLng(maxLat + latPad, maxLng + lngPad),
        ),
        50,
      ),
    );
  }

  void _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadTrack();
    }
  }

  bool _isPlaying = false;
  Timer? _playTimer;

  void _togglePlayback() {
    if (_isPlaying) {
      _playTimer?.cancel();
      setState(() => _isPlaying = false);
      return;
    }
    if (_points.length < 2) return;

    setState(() => _isPlaying = true);
    const interval = Duration(milliseconds: 500);

    _playTimer = Timer.periodic(interval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final nextVal = _sliderValue + 1;
      if (nextVal >= _points.length - 1) {
        timer.cancel();
        setState(() {
          _sliderValue = (_points.length - 1).toDouble();
          _isPlaying = false;
        });
        return;
      }
      setState(() => _sliderValue = nextVal);
      final p = _points[nextVal.toInt()];
      _mapController?.moveCamera(
        CameraUpdate.newLatLng(LatLng(p['lat'] as double, p['lng'] as double)),
      );
    });
  }

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h时$m分$s秒';
    }
    return '$m分$s秒';
  }

  /// Build a GPX 1.1 XML string from the current track points.
  String _buildGpxXml() {
    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
        '<gpx version="1.1" creator="FieldTracker" xmlns="http://www.topografix.com/GPX/1/1">');
    buf.writeln('  <metadata>');
    buf.writeln('    <name>Track $dateStr</name>');
    buf.writeln('    <time>${_formatGpxTime(DateTime.now())}</time>');
    buf.writeln('  </metadata>');
    buf.writeln('  <trk>');
    buf.writeln('    <name>Track $dateStr</name>');
    buf.writeln('    <trkseg>');
    for (final p in _points) {
      final lat = p['lat'];
      final lng = p['lng'];
      final ts = p['timestamp'];
      if (lat == null || lng == null) continue;
      buf.write('      <trkpt lat="$lat" lon="$lng">');
      if (ts != null) {
        buf.write(
            '<time>${_formatGpxTime(DateTime.fromMillisecondsSinceEpoch(ts as int))}</time>');
      }
      buf.writeln('</trkpt>');
    }
    buf.writeln('    </trkseg>');
    buf.writeln('  </trk>');
    buf.writeln('</gpx>');
    return buf.toString();
  }

  /// Format a [DateTime] as ISO 8601 UTC for GPX <time>.
  String _formatGpxTime(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year.toString();
    final mo = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final mi = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:${s}Z';
  }

  /// Export the current track as a GPX file and share via the system share sheet.
  Future<void> _exportGpx() async {
    if (_points.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有轨迹数据可导出')),
        );
      }
      return;
    }

    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/track-$dateStr.gpx');
      await file.writeAsString(_buildGpxXml());

      final size = await file.length();
      if (size == 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导出失败：生成的 GPX 文件为空')),
          );
        }
        return;
      }

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '轨迹 - $dateStr',
        text: '轨迹回放 - $dateStr',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出轨迹失败: $e')),
        );
      }
    }
  }

  /// 速度图例条
  Widget _buildSpeedLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem(const Color(0xFF4CAF50), '<1'),
          const SizedBox(width: 12),
          _legendItem(const Color(0xFFFFEB3B), '1~5'),
          const SizedBox(width: 12),
          _legendItem(const Color(0xFFFF9800), '5~20'),
          const SizedBox(width: 12),
          _legendItem(const Color(0xFFF44336), '>20'),
          const Text(' km/h',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 6,
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = _points.isNotEmpty
        ? _sliderValue.toInt().clamp(0, _points.length - 1)
        : 0;
    final currentPos = _points.isNotEmpty ? _points[currentIdx] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('轨迹回放'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出 GPX',
            onPressed: _points.isNotEmpty ? _exportGpx : null,
          ),
          IconButton(
              icon: const Icon(Icons.date_range), onPressed: _selectDate),
        ],
      ),
      body: Column(
        children: [
          // 日期栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  '${_points.length} 个轨迹点',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // 统计摘要卡片
          if (_points.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.blue.withOpacity(0.03),
              child: Row(
                children: [
                  _statItem(Icons.route,
                      '${_totalDistanceKm.toStringAsFixed(2)} km', '总距离'),
                  Container(
                    width: 1,
                    height: 32,
                    color: Colors.grey[300],
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  _statItem(Icons.speed,
                      '${_avgSpeedKmh.toStringAsFixed(1)} km/h', '平均速度'),
                  Container(
                    width: 1,
                    height: 32,
                    color: Colors.grey[300],
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  _statItem(Icons.timer, _formatDuration(_totalDuration), '时长'),
                ],
              ),
            ),

          // 速度图例
          if (_points.length > 1) _buildSpeedLegend(),

          // 地图区域
          Expanded(
            flex: 3,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: TextStyle(color: Colors.grey[600])),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: _loadTrack, child: const Text('重试')),
                          ],
                        ),
                      )
                    : _points.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.route,
                                    size: 48, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text('当天无轨迹数据',
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 15)),
                              ],
                            ),
                          )
                        : AMapWidget(
                            apiKey: AMapApiKey(
                              androidKey: AMapConfig.androidKey,
                              iosKey: AMapConfig.iosKey,
                            ),
                            privacyStatement: const AMapPrivacyStatement(
                              hasContains: true,
                              hasShow: true,
                              hasAgree: true,
                            ),
                            initialCameraPosition: CameraPosition(
                              target: LatLng(currentPos!['lat'] as double,
                                  currentPos['lng'] as double),
                              zoom: 15,
                            ),
                            onMapCreated: (controller) {
                              _mapController = controller;
                              _fitMapToTrack(_points
                                  .map((p) => LatLng(
                                      p['lat'] as double, p['lng'] as double))
                                  .toList());
                            },
                            polylines: _polylines,
                            markers: _markers,
                            compassEnabled: true,
                            scaleEnabled: true,
                            zoomGesturesEnabled: true,
                            scrollGesturesEnabled: true,
                            myLocationStyleOptions:
                                MyLocationStyleOptions(true),
                          ),
          ),

          // 列表切换按钮 + 轨迹点列表
          if (_points.isNotEmpty)
            Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() {
                      _showPointList = !_showPointList;
                      if (_showPointList && _pointListScrollController.hasClients) {
                        _pointListScrollController.animateTo(
                          0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _showPointList ? Icons.unfold_less : Icons.unfold_more,
                            size: 16, color: Colors.blue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showPointList ? '收起轨迹点列表' : '展开轨迹点列表 (${_points.length}个点)',
                            style: const TextStyle(fontSize: 13, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showPointList)
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        controller: _pointListScrollController,
                        itemCount: _points.length,
                        itemBuilder: (_, i) {
                          final p = _points[i];
                          final lat = p['lat'] as double;
                          final lng = p['lng'] as double;
                          final ts = p['timestamp'] as int;
                          final acc = p['accuracy'] as double? ?? 0;
                          final spd = p['speed'] as double?;
                          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                          final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                          return InkWell(
                            onTap: () {
                              setState(() => _sliderValue = i.toDouble());
                              _mapController?.moveCamera(
                                CameraUpdate.newLatLng(LatLng(lat, lng)),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: i == _sliderValue.toInt()
                                    ? Colors.blue.withOpacity(0.08)
                                    : null,
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 36,
                                    child: Text(
                                      '#${i + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: i == _sliderValue.toInt() ? Colors.blue : Colors.grey[500],
                                        fontWeight: i == _sliderValue.toInt() ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 72,
                                    child: Text(timeStr,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      '精度${acc.toStringAsFixed(0)}m',
                                      style: TextStyle(fontSize: 10, color: acc < 15 ? Colors.green : Colors.grey[600]),
                                    ),
                                  ),
                                  if (spd != null)
                                    SizedBox(
                                      width: 44,
                                      child: Text(
                                        '${(spd * 3.6).toStringAsFixed(1)}km/h',
                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

          // 当前位置信息
          if (currentPos != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.blue.withOpacity(0.05),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 6),
                  Text(
                    '${currentPos['lat'].toStringAsFixed(4)}, ${currentPos['lng'].toStringAsFixed(4)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(currentPos['timestamp'] as int),
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),

          // 底部控制栏
          if (_points.length > 1)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(_formatTime(_points.first['timestamp'] as int),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Expanded(
                        child: Slider(
                          value: _sliderValue,
                          min: 0,
                          max: (_points.length - 1).toDouble(),
                          divisions: _points.length - 1,
                          onChanged: (v) {
                            setState(() => _sliderValue = v);
                            final p = _points[v.toInt()];
                            _mapController?.moveCamera(
                              CameraUpdate.newLatLng(LatLng(
                                  p['lat'] as double, p['lng'] as double)),
                            );
                          },
                          activeColor: Colors.blue,
                        ),
                      ),
                      Text(_formatTime(_points.last['timestamp'] as int),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            size: 40,
                            color: Colors.blue),
                        onPressed: _togglePlayback,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 统计项组件
  Widget _statItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.blue[600]),
              const SizedBox(width: 4),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
