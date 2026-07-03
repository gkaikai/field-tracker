// 轨迹回放页面

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final userId = AuthService().userId ?? 'me';
      final resp = await _api.get('/api/v1/location/track/$userId', query: {'date': dateStr});
      final data = resp.data as Map<String, dynamic>;
      final points = (data['points'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _points = points;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载轨迹失败: $e';
        _isLoading = false;
      });
    }
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

  String _formatCoord(double val) => val.toStringAsFixed(4);
  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('轨迹回放'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.date_range), onPressed: _selectDate),
        ],
      ),
      body: Column(
        children: [
          // 日期选择
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  '${_points.length} 个轨迹点',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // 轨迹信息
          Expanded(child: _buildTrackView()),

          // 底部时间轴
          if (_points.length > 1)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(_points.first['timestamp'] as int),
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(_formatTime(_points.last['timestamp'] as int),
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  Slider(
                    value: _sliderValue,
                    min: 0,
                    max: (_points.length - 1).toDouble(),
                    divisions: _points.length - 1,
                    onChanged: (v) => setState(() => _sliderValue = v),
                    activeColor: Colors.blue,
                  ),
                  if (_points.isNotEmpty) ...[
                    Text(
                      '位置: ${_formatCoord(_points[_sliderValue.toInt()]['lat'] as double)}, ${_formatCoord(_points[_sliderValue.toInt()]['lng'] as double)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '时间: ${_formatTime(_points[_sliderValue.toInt()]['timestamp'] as int)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadTrack, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_points.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('当天无轨迹数据', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          ],
        ),
      );
    }

    // 轨迹概要列表
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _points.length,
      itemBuilder: (_, i) {
        final p = _points[i];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: i == _sliderValue.toInt() ? Colors.blue : Colors.grey[200],
            child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: i == _sliderValue.toInt() ? Colors.white : Colors.grey[600])),
          ),
          title: Text('${_formatCoord(p['lat'] as double)}, ${_formatCoord(p['lng'] as double)}', style: const TextStyle(fontSize: 13)),
          subtitle: Text('速度: ${(p['speed'] as num?)?.toStringAsFixed(1) ?? "0"} m/s', style: const TextStyle(fontSize: 11)),
          trailing: Text(_formatTime(p['timestamp'] as int), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          selected: i == _sliderValue.toInt(),
          selectedTileColor: Colors.blue.withOpacity(0.05),
        );
      },
    );
  }
}
