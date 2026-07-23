// 轨迹回放页面 - 地图版（适配 amap_flutter_map 3.0.0 API）

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:math' show cos, sin, pi;

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

class _TrackReplayPageState extends State<TrackReplayPage> with WidgetsBindingObserver {
  final ApiService _api = ApiService();

  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _points = [];
  bool _isLoading = false;
  String? _error;
  double _sliderValue = 0;
  int? _lastFetchedTimestamp;
  bool _isLoadingTrack = false; // 请求去重锁
  bool _isForeground = true;    // APP是否在前台

  AMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Set<Polygon> _fencePolygons = {};

  // 轨迹统计
  double _totalDistanceKm = 0;
  // 轨迹列表已移除（数据量大，后台存着即可）
  double _avgSpeedKmh = 0;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTrack();
    _loadFences();
    // 每15秒自动刷新轨迹（仅前台有效，省电省流量）
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!mounted || !_isForeground) return;
        if (!_isPlaying) _loadTrack(isAutoRefresh: true);
      },
    );
  }
  Future<void> _loadTrack({bool isAutoRefresh = false}) async {
    if (_isLoadingTrack) return; // 请求去重
    _isLoadingTrack = true;
    
    if (!isAutoRefresh) {
      setState(() {
        _isLoading = true;
        _error = null;
        _sliderValue = 0;
      });
    }

    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final auth = AuthService();
      final userId = auth.userId ?? 'me';

      // 自动刷新时只拉增量数据（since=最新时间戳）
      // 全量首次加载时不传since，拉取当天全部数据
      final queryParams = <String, dynamic>{'date': dateStr};
      if (isAutoRefresh && _lastFetchedTimestamp != null) {
        queryParams['since'] = _lastFetchedTimestamp.toString();
      }

      final resp = await _api.get(
        '/api/v1/location/track/$userId',
        query: queryParams,
      );
      if (!mounted) return;
      final data = resp.data as Map<String, dynamic>;
      final newPoints =
          (data['points'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final latestTimestamp = data['latestTimestamp'] as int?;

      if (!mounted) return;

      setState(() {
        if (isAutoRefresh && _lastFetchedTimestamp != null) {
          // 增量模式：追加新数据
          if (newPoints.isNotEmpty) {
            final oldLen = _points.length;
            _points = [..._points, ...newPoints];
            // 增量更新地图：仅从 oldLen-1 开始追加新段
            try {
              _updateMap(fitToTrack: false, incrementalFrom: oldLen);
            } catch (mapErr, mapSt) {
              debugPrint('=== _updateMap error ===\n$mapErr\n$mapSt');
            }
          }
        } else {
          // 全量模式：替换全部数据 + 重置进度条
          _points = newPoints;
          _sliderValue = 0;
        }
        _isLoading = false;
        _sliderValue = _sliderValue.clamp(0, _points.isNotEmpty ? (_points.length - 1).toDouble() : 0);
      });

      // 更新最后时间戳
      if (latestTimestamp != null) {
        _lastFetchedTimestamp = latestTimestamp;
      }

      // 全量模式才需要在这里调 _updateMap（增量已在 setState 内处理）
      if (!isAutoRefresh) {
        try {
          _updateMap(fitToTrack: true);
        } catch (mapErr, mapSt) {
          debugPrint('=== _updateMap error ===\n$mapErr\n$mapSt');
        }
      }
    } catch (e, st) {
      if (!mounted) return;
      final detail = e.toString();
      final errMsg = '加载轨迹失败${detail.isNotEmpty ? ': [${e.runtimeType}] $detail' : ''}';
      debugPrint('=== _loadTrack error ===\n$e\n$st');
      if (!isAutoRefresh) {
        setState(() {
          _error = errMsg;
          _isLoading = false;
        });
      }
    } finally {
      _isLoadingTrack = false;
    }
  }

  /// 加载电子围栏并渲染为红色多边形
  Future<void> _loadFences() async {
    try {
      final resp = await _api.get('/api/v1/fences');
      final List<dynamic> raw = resp.data is List
          ? resp.data
          : (resp.data['data'] ?? resp.data['fences'] ?? []);
      final fences = <Polygon>{};
      for (final f in raw) {
        final fence = f as Map<String, dynamic>;
        final shapeType = fence['shapeType'] as String? ?? 'circle';
        if (shapeType == 'circle') {
          final lat = fence['centerLat'] as num?;
          final lng = fence['centerLng'] as num?;
          final radius = fence['radiusMeters'] as num? ?? 300;
          if (lat == null || lng == null) continue;
          fences.add(Polygon(
            points: _circlePolygonPoints(LatLng(lat.toDouble(), lng.toDouble()), radius.toDouble()),
            strokeWidth: 3,
            strokeColor: Colors.red,
            fillColor: Colors.red.withOpacity(0.10),
          ));
        } else if (shapeType == 'polygon') {
          final coords = fence['coordinates'] as List<dynamic>?;
          if (coords == null || coords.length < 3) continue;
          final pts = coords.map((c) {
            if (c is Map<String, dynamic>) {
              return LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
            }
            final cList = c as List<dynamic>;
            return LatLng((cList[1] as num).toDouble(), (cList[0] as num).toDouble());
          }).toList();
          fences.add(Polygon(
            points: pts,
            strokeWidth: 3,
            strokeColor: Colors.red,
            fillColor: Colors.red.withOpacity(0.10),
          ));
        }
      }
      if (mounted) setState(() => _fencePolygons = fences);
    } catch (e) {
      debugPrint('[TrackReplay] 加载围栏失败: $e');
    }
  }

  /// 生成近似圆形的多边形点
  List<LatLng> _circlePolygonPoints(LatLng center, double radiusMeters) {
    const n = 64;
    const latPerM = 1.0 / 111320.0;
    final lngPerM = 1.0 / (111320.0 * cos(center.latitude * pi / 180.0));
    return List.generate(n, (i) {
      final angle = 2 * pi * i / n;
      return LatLng(
        center.latitude + radiusMeters * cos(angle) * latPerM,
        center.longitude + radiusMeters * sin(angle) * lngPerM,
      );
    });
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

  void _updateMap({bool fitToTrack = true, int incrementalFrom = 0}) {
    if (_points.isEmpty) return;

    double totalDistKm = 0;
    int totalDurationMs = 0;

    // 总距离/时间直接从已有值继承（增量模式）或从零开始（全量模式）
    if (incrementalFrom > 0) {
      totalDistKm = _totalDistanceKm;
    }

    final List<Polyline> newPolylines = [];

    if (_points.length > 1) {
      // 增量模式：从 incrementalFrom-1 开始只计算新增段
      // 全量模式：从 0 开始
      final startIdx = incrementalFrom > 0
          ? (incrementalFrom - 1).clamp(0, _points.length - 2)
          : 0;

      for (int i = startIdx; i < _points.length - 1; i++) {
        final p1 = _points[i];
        final p2 = _points[i + 1];

        final lat1 = p1['lat'] as double;
        final lng1 = p1['lng'] as double;
        final lat2 = p2['lat'] as double;
        final lng2 = p2['lng'] as double;

        final t1 = p1['timestamp'] as int;
        final t2 = p2['timestamp'] as int;
        final gapSec = (t2 - t1).abs() ~/ 1000;
        if (gapSec > 300) continue;

        // 增量模式：跳过重叠段的距离（已在_totalDistanceKm中计过）
        if (!(incrementalFrom > 0 && i == startIdx)) {
          totalDistKm += _haversineDistance(lat1, lng1, lat2, lng2) / 1000.0;
        }

        final speedKmh = _getSegmentSpeed(p1, p2);
        newPolylines.add(Polyline(
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
      // 单点
      final p = _points.first;
      newPolylines.add(Polyline(
        points: [LatLng(p['lat'] as double, p['lng'] as double)],
        color: const Color(0xFF4CAF50).withOpacity(0.7),
        width: 6,
      ));
    }

    // 当前点位标记（小蓝点）
    final markers = <Marker>{};
    if (_points.isNotEmpty) {
      final currentIdx = _sliderValue.toInt().clamp(0, _points.length - 1);
      final current = _points[currentIdx];
      
      // 起点标记（绿点）
      if (_points.length > 1) {
        final first = _points.first;
        markers.add(Marker(
          position: LatLng(first['lat'] as double, first['lng'] as double),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: '起点'),
        ));
        // 终点标记（红点）
        final last = _points.last;
        markers.add(Marker(
          position: LatLng(last['lat'] as double, last['lng'] as double),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: '终点'),
        ));
      }

      // 当前定位小蓝点
      markers.add(Marker(
        position: LatLng(current['lat'] as double, current['lng'] as double),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: _formatTime(current['timestamp'] as int),
          snippet: '${current['lat'].toStringAsFixed(5)}, ${current['lng'].toStringAsFixed(5)}',
        ),
      ));
    }

    setState(() {
      if (incrementalFrom > 0) {
        // 增量追加：保留旧折线 + 追加新段
        _polylines = {..._polylines, ...newPolylines};
      } else {
        // 全量重建
        _polylines = newPolylines.toSet();
      }
      _markers = markers;
      _totalDistanceKm = totalDistKm;
      _totalDuration = Duration(milliseconds: totalDurationMs);
      _avgSpeedKmh = totalDurationMs > 0
          ? (totalDistKm / (totalDurationMs / 3600000.0))
          : 0;
    });

    if (fitToTrack) {
      _fitMapToTrack(
        _points
            .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
            .toList(),
      );
    }
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

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();

    // 如果轨迹跨度太大（如跨城市），不要缩到全国，
    // 而是缩放到第一个点附近的可视范围（zoom=14）
    if (latSpan > 0.5 || lngSpan > 0.5) {
      // 跨城市：居中在第一个点附近
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: points.first,
            zoom: 14,
          ),
        ),
      );
      return;
    }

    // 正常局部轨迹：缩放到刚好显示所有点
    final latPad = ((maxLat - minLat) * 0.3).clamp(0.001, 0.02);
    final lngPad = ((maxLng - minLng) * 0.3).clamp(0.001, 0.02);

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

  /// 更新当前定位标记（滑块/播放时触发）
  void _updateCurrentMarker() {
    if (_points.isEmpty) return;
    final currentIdx = _sliderValue.toInt().clamp(0, _points.length - 1);
    final current = _points[currentIdx];
    
    setState(() {
      final markers = <Marker>{};
      if (_points.length > 1) {
        final first = _points.first;
        markers.add(Marker(
          position: LatLng(first['lat'] as double, first['lng'] as double),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: '起点'),
        ));
        final last = _points.last;
        markers.add(Marker(
          position: LatLng(last['lat'] as double, last['lng'] as double),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: '终点'),
        ));
      }
      markers.add(Marker(
        position: LatLng(current['lat'] as double, current['lng'] as double),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: _formatTime(current['timestamp'] as int),
          snippet: '${current['lat'].toStringAsFixed(5)}, ${current['lng'].toStringAsFixed(5)}',
        ),
      ));
      _markers = markers;
    });
  }

  void _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _lastFetchedTimestamp = null;
      });
      _loadTrack();
    }
  }

  bool _isPlaying = false;
  bool _playbackFinished = false; // 防止播放结束重置与快速重播的竞态
  Timer? _playTimer;
  double _playSpeed = 1.0; // 播放倍速: 1x, 2x, 4x, 8x
  static const List<double> _speedOptions = [1.0, 2.0, 4.0, 8.0];

  // 自动刷新（实时轨迹）
  Timer? _autoRefreshTimer;

  void _togglePlayback() {
    if (_isPlaying) {
      _playTimer?.cancel();
      setState(() => _isPlaying = false);
      return;
    }
    if (_points.length < 2) return;

    setState(() {
      _isPlaying = true;
      _playbackFinished = false;
    });
    final intervalMs = (500 / _playSpeed).round();
    final interval = Duration(milliseconds: intervalMs.clamp(16, 5000));

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
          // 重置播放起点，下次播放从头开始
        });
        // 播放结束后重置到起点
        _playbackFinished = true;
        Future.delayed(Duration.zero, () {
          if (mounted && _playbackFinished) {
            setState(() => _sliderValue = 0);
          }
        });
        return;
      }
      setState(() => _sliderValue = nextVal);
      _updateCurrentMarker();
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
    WidgetsBinding.instance.removeObserver(this);
    _playTimer?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    // 回到前台立即刷新，不等下次定时器 tick
    if (!_isForeground || !mounted || _isPlaying) return;
    _loadTrack(isAutoRefresh: true);
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '手动刷新',
            onPressed: () => _loadTrack(isAutoRefresh: false),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部：日期栏
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
          // 地图区域 — 占剩余空间，独立手势
          Expanded(
            child: Stack(
              children: [
                // 地图底图始终加载（不依赖轨迹数据）
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
                    onMapCreated: (controller) {
                      _mapController = controller;
                      if (_points.isNotEmpty) _fitMapToTrack(
                        _points.map((p) => LatLng(p['lat'] as double, p['lng'] as double)).toList(),
                      );
                    },
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(22.543096, 114.057865),
                      zoom: 15,
                    ),
                    polylines: _polylines,
                    markers: _markers,
                    polygons: _fencePolygons,
                    compassEnabled: true,
                    scaleEnabled: true,
                    zoomGesturesEnabled: true,
                    scrollGesturesEnabled: true,
                  ),
                // 加载中遮罩
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
                // 无轨迹提示
                if (!_isLoading && _error == null && _points.isEmpty)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.route, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('当天无轨迹数据',
                            style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                      ],
                    ),
                  ),
                // 错误提示（不影响地图底图展示）
                if (!_isLoading && _error != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.orange[700], size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_error!, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() => _error = null);
                                _loadTrack();
                              },
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 底部固定区域：当前位置 + 播放控制 + 点列表切换
          if (_points.isNotEmpty)
            Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 当前位置信息
                  if (currentPos != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      color: Colors.blue.withOpacity(0.05),
                      child: Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: Colors.blue[700]),
                          const SizedBox(width: 4),
                          Text(
                            '${currentPos['lat'].toStringAsFixed(4)}, ${currentPos['lng'].toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          const Icon(Icons.access_time, size: 12, color: Colors.grey),
                          const SizedBox(width: 2),
                          Text(
                            _formatTime(currentPos['timestamp'] as int),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  // 底部控制栏
                  if (_points.length > 1)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(_formatTime(_points.first['timestamp'] as int),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Expanded(
                                child: Slider(
                                  value: _sliderValue,
                                  min: 0,
                                  max: (_points.length - 1).toDouble(),
                                  divisions: _points.length - 1,
                                  label: _formatTime(_points[_sliderValue.toInt()]['timestamp'] as int),
                                  onChanged: (v) {
                                    setState(() => _sliderValue = v);
                                    _updateCurrentMarker();
                                  },
                                ),
                              ),
                              Text(_formatTime(_points.last['timestamp'] as int),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ..._speedOptions.map((speed) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: FilterChip(
                                  label: Text('${speed.toInt()}x', style: const TextStyle(fontSize: 11)),
                                  selected: _playSpeed == speed,
                                  onSelected: _isPlaying ? null : (v) {
                                    if (v) setState(() => _playSpeed = speed);
                                  },
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              )),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_filled,
                                    size: 36,
                                    color: Colors.blue),
                                onPressed: _togglePlayback,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  // 点列表已移除（后台存储，前台不展示）
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
