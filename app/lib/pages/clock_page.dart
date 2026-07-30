// 打卡签到页面 v2 — 大圆环时钟 + 签到/签退对比 + 规则提示
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/error_codes.dart';
import '../services/amap_location_service.dart';
import '../utils/time_utils.dart';
import '../theme/app_theme.dart';
import 'attendance_page.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});
  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _isClocking = false;
  String? _resultMessage;
  String? _resultType;

  // GPS
  double? _lat;
  double? _lng;
  double? _accuracy;
  String? _address;
  bool _gpsReady = false;

  // Today's status
  bool _checkedIn = false;
  bool _checkedOut = false;
  String? _checkinTime;
  String? _checkoutTime;
  Timer? _gpsTimer;
  Timer? _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _startGpsPolling();
    _updateClock();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _updateClock() {
    // 每秒更新时钟显示
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          final now = DateTime.now();
          _currentTime =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
        });
      }
    });
  }

  void _startGpsPolling() {
    _updateGps();
    _gpsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _updateGps();
    });
  }

  void _updateGps() {
    final loc = AmapLocationService();
    if (loc.currentLat != null && loc.currentLng != null) {
      setState(() {
        _lat = loc.currentLat;
        _lng = loc.currentLng;
        _accuracy = loc.currentAccuracy;
        _gpsReady = true;
      });
    }
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    try {
      final resp = await _api.get('/api/v1/attendance/my-status');
      final data = resp.data as Map<String, dynamic>;
      final today = data['today'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          _checkedIn = today['checkedIn'] == true;
          _checkedOut = today['checkedOut'] == true;
          final records = (today['records'] as List?) ?? [];
          for (final r in records) {
            final rm = r as Map<String, dynamic>;
            if (rm['type'] == 'checkin') {
              _checkinTime = rm['check_time'] as String?;
            } else if (rm['type'] == 'checkout') {
              _checkoutTime = rm['check_time'] as String?;
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _showResult('error', '加载打卡状态失败'); });
    }
  }

  Future<void> _doClock(String type) async {
    if (_isClocking) return;
    if (!_gpsReady) { _showResult('error', '⚠️ GPS定位未就绪，请稍后重试'); return; }
    setState(() { _isClocking = true; _resultMessage = null; _resultType = null; });
    try {
      final resp = await _api.post('/api/v1/attendance/checkin', data: {
        'type': type, 'lat': _lat, 'lng': _lng, 'accuracy': _accuracy ?? 0, 'address': _address ?? '',
      });
      final data = resp.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final clockType = type == 'checkin' ? '签到' : '签退';
        final t = data['checkTime'] as String?;
        _showResult('success', '✅ $clockType成功${t != null ? ' ${formatTimestamp(t, showSeconds: true)}' : ''}');
        await _loadStatus();
      } else {
        _showResult('error', '❌ 打卡失败: ${data['message'] ?? '未知错误'}');
      }
    } catch (e) {
      String msg = '❌ 打卡失败';
      if (e is ApiException) msg = '❌ ${e.friendlyMessage}';
      _showResult('error', msg);
    } finally {
      if (mounted) setState(() => _isClocking = false);
    }
  }

  void _showResult(String type, String message) {
    if (!mounted) return;
    setState(() { _resultType = type; _resultMessage = message; });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() { _resultMessage = null; _resultType = null; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡签到'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AttendancePage(),
            )),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatus,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Result banner
                    if (_resultMessage != null) _buildResultBanner(),

                    // GPS status
                    _buildGpsCard(context),

                    const SizedBox(height: 24),

                    // Big circular clock
                    _buildClockCircle(context),

                    const SizedBox(height: 24),

                    // Check-in / Check-out comparison
                    _buildStatusComparison(),

                    const SizedBox(height: 24),

                    // Clock button
                    _buildClockButton(context),

                    const SizedBox(height: 16),

                    // Rules card
                    _buildRulesCard(context),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildResultBanner() {
    Color bg, iconColor;
    switch (_resultType) {
      case 'success': bg = const Color(0xFFF0FDF4); iconColor = const Color(0xFF16A34A); break;
      case 'late': bg = const Color(0xFFFFFBEB); iconColor = const Color(0xFFF59E0B); break;
      case 'outside': bg = const Color(0xFFFFFBEB); iconColor = const Color(0xFFF59E0B); break;
      default: bg = const Color(0xFFFEF2F2); iconColor = const Color(0xFFDC2626);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: iconColor.withOpacity(0.3))),
      child: Row(children: [
        Icon(Icons.info_outline, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(_resultMessage ?? '', style: TextStyle(color: iconColor, fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _buildGpsCard(BuildContext context) {
    final green = context.successColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _gpsReady ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gpsReady ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _gpsReady ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.gps_fixed, color: _gpsReady ? green : const Color(0xFFF59E0B), size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_gpsReady ? 'GPS 定位正常' : 'GPS 定位中...',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _gpsReady ? green : const Color(0xFFF59E0B))),
            if (_lat != null) Text('精度: ${_accuracy?.toStringAsFixed(0) ?? "?"}m · ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildClockCircle(BuildContext context) {
    final theme = Theme.of(context);
    final color = _checkedIn ? const Color(0xFF2563EB) : Colors.grey.shade400;
    return Column(
      children: [
        Container(
          width: 200, height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 5),
            color: _checkedIn ? const Color(0xFFEFF6FF) : Colors.grey.shade50,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _checkinTime != null
                    ? formatTimestamp(_checkinTime!, showSeconds: true)
                    : _currentTime.isNotEmpty ? _currentTime : '--:--:--',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                _checkedIn ? (_checkedOut ? '✅ 已完成' : '✅ 已签到') : '⏳ 待签到',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(_checkedIn ? (_checkedOut ? '今日工作已完成' : '工作中') : '请进行上班打卡',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildStatusComparison() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Check-in
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _checkedIn ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
              child: Column(children: [
                Icon(Icons.login, size: 28, color: _checkedIn ? const Color(0xFF16A34A) : Colors.grey.shade400),
                const SizedBox(height: 6),
                Text('上班', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(_checkedIn && _checkinTime != null ? formatTimestamp(_checkinTime!, showSeconds: true) : '未打卡',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: _checkedIn ? const Color(0xFF16A34A) : Colors.grey.shade400)),
              ]),
            ),
          ),
          Container(width: 1, height: 80, color: Colors.grey.shade200),
          // Check-out
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _checkedOut ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
              ),
              child: Column(children: [
                Icon(Icons.logout, size: 28, color: _checkedOut ? const Color(0xFF16A34A) : Colors.grey.shade400),
                const SizedBox(height: 6),
                Text('下班', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(_checkedOut && _checkoutTime != null ? formatTimestamp(_checkoutTime!, showSeconds: true) : '未打卡',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: _checkedOut ? const Color(0xFF16A34A) : Colors.grey.shade400)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClockButton(BuildContext context) {
    if (!_checkedIn) {
      return SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton.icon(
          onPressed: _isClocking ? null : () => _doClock('checkin'),
          icon: _isClocking
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.login, size: 22),
          label: Text(_isClocking ? '签到中...' : '上班签到', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      );
    } else if (!_checkedOut) {
      return SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton.icon(
          onPressed: _isClocking ? null : () => _doClock('checkout'),
          icon: _isClocking
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.logout, size: 22),
          label: Text(_isClocking ? '签退中...' : '下班打卡', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      );
    } else {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Column(children: [
          const Icon(Icons.check_circle, size: 48, color: Color(0xFF16A34A)),
          const SizedBox(height: 8),
          const Text('今日打卡已完成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
          const SizedBox(height: 4),
          Text('上班: ${_checkinTime != null ? formatTimestamp(_checkinTime!, showSeconds: true) : '—'}  下班: ${_checkoutTime != null ? formatTimestamp(_checkoutTime!, showSeconds: true) : '—'}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ]),
      );
    }
  }

  Widget _buildRulesCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text('今日考勤规则', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        ]),
        const SizedBox(height: 10),
        _ruleRow('⏰', '上下班时间', '09:00 - 18:00'),
        _ruleRow('📍', '打卡范围', '公司 100m 内'),
        _ruleRow('📅', '工作日', '周一至周五'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, size: 14, color: Color(0xFF16A34A)),
            SizedBox(width: 4),
            Text('当前在打卡区域内', style: TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }

  Widget _ruleRow(String icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
