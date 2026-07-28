import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import '../config/app_config.dart';
import '../utils/geo_convert.dart' show haversineMeters;

/// 活动状态枚举
enum MotionState {
  /// 移动中 — GPS速度>1m/s 或 加速度有振动
  moving,
  /// 不确定期 — 可能即将静止的缓冲过渡
  uncertain,
  /// 真正静止 — 三条件全部满足
  stationary,
}

/// 活动状态机 + 加速度传感器管理
///
/// 三信号融合：
/// 1. GPS speed（最高优先级）
/// 2. 加速度传感器（辅助判断低速/盲区）
/// 3. 累计位移（兜底）
class MotionDetector {
  static final MotionDetector _instance = MotionDetector._internal();
  factory MotionDetector() => _instance;
  MotionDetector._internal();

  // ─── 当前状态 ───
  MotionState _state = MotionState.moving;
  MotionState get state => _state;

  // ─── 加速度数据 ───
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  final List<double> _recentAccelVariance = [];
  bool _hasAccelerometer = false;
  bool _personMoving = true; // 加速度判断的人体活动状态

  // ─── 静止基准点 ───
  double? _stillBaseLat;
  double? _stillBaseLng;

  // ─── 时间记录 ───
  DateTime? _uncertainStartTime;
  DateTime? _lowSpeedStartTime;
  DateTime? _stillStartTime;

  // ─── 监听器 ───
  void Function(MotionState state)? onStateChanged;

  /// 获取当前建议的上传间隔
  int get uploadInterval {
    switch (_state) {
      case MotionState.moving:
        return AppConfig.movingUploadInterval;
      case MotionState.uncertain:
        return AppConfig.uncertainUploadInterval;
      case MotionState.stationary:
        return AppConfig.stationaryUploadInterval;
    }
  }

  // ============================================================
  //  启动/停止
  // ============================================================

  /// 启动加速度传感器监听
  Future<void> start() async {
    _resetState();

    try {
      _accelSubscription = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 
          AppConfig.accelerometerSampleIntervalMs),
      ).listen(
        (AccelerometerEvent event) {
          _handleAccelerometer(event);
        },
        onError: (_) {
          _hasAccelerometer = false;
        },
      );
      _hasAccelerometer = true;
    } catch (_) {
      _hasAccelerometer = false;
    }
  }

  /// 停止加速度传感器
  void stop() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _hasAccelerometer = false;
    _recentAccelVariance.clear();
    _state = MotionState.moving;
    _stillBaseLat = null;
    _stillBaseLng = null;
  }

  void _resetState() {
    _state = MotionState.moving;
    _stillBaseLat = null;
    _stillBaseLng = null;
    _uncertainStartTime = null;
    _lowSpeedStartTime = null;
    _stillStartTime = null;
    _recentAccelVariance.clear();
    _personMoving = true;
  }

  // ============================================================
  //  加速度数据处理
  // ============================================================

  void _handleAccelerometer(AccelerometerEvent event) {
    // 计算净加速度幅值 = 去掉重力后的波动大小
    // sensors_plus 返回 m/s²，静止时受重力 ~9.8 m/s²
    // sqrt(x² + y² + z²) 得到总幅值，减去重力 9.8 得净波动
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final netAccel = (magnitude - 9.8).abs();

    _recentAccelVariance.add(netAccel);
    if (_recentAccelVariance.length > AppConfig.accelConsecutiveSamples) {
      _recentAccelVariance.removeAt(0);
    }

    // 连续N次采样都低于静止阈值 → 判定无人体活动
    if (_recentAccelVariance.length >= AppConfig.accelConsecutiveSamples) {
      final allStill = _recentAccelVariance
          .every((v) => v < AppConfig.accelStillThreshold);
      final allMoving = _recentAccelVariance
          .every((v) => v > AppConfig.accelWalkThreshold);

      if (allStill) {
        _personMoving = false;
      } else if (allMoving) {
        _personMoving = true;
      }
    }
  }

  /// 加速度判断是否有振动（人体活动）
  bool get hasAccelActivity => _personMoving;

  /// 加速度传感器是否可用
  bool get isAccelerometerAvailable => _hasAccelerometer;

  // ============================================================
  //  状态机 — 核心判定（由 LocationService 每次收到GPS后调用）
  // ============================================================

  /// 传入本次GPS数据，更新活动状态
  /// [speed] GPS速度（m/s），null=丢失
  /// [gpsLost] GPS是否丢失（独立参数，避免speed=null被误判为静止）
  /// [cumulativeDisplacement] 从静止基准点的累计位移（米）
  /// [currentLat] 当前纬度（用于更新基准点）
  /// [currentLng] 当前经度
  void updateState({
    required double? speed,
    required bool gpsLost,
    required double cumulativeDisplacement,
    double? currentLat,
    double? currentLng,
  }) {
    final now = DateTime.now();

    // ── A) GPS速度 > 阈值 → 直接MOVING ──
    if (!gpsLost && speed != null && speed > AppConfig.movingSpeedThreshold) {
      _transitionTo(MotionState.moving);
      _uncertainStartTime = null;
      _lowSpeedStartTime = null;
      // 重置静止基准点
      if (currentLat != null && currentLng != null) {
        _stillBaseLat = currentLat;
        _stillBaseLng = currentLng;
      }
      return;
    }

    // ── B) GPS速度 < 阈值 或 丢失 → 检查累计位移 ──
    if (cumulativeDisplacement > AppConfig.cumulativeMoveThreshold) {
      // 累计位移过大 → 兜底：人在移动
      _transitionTo(MotionState.moving);
      _uncertainStartTime = null;
      _lowSpeedStartTime = null;
      // 重置基准点
      if (currentLat != null && currentLng != null) {
        _stillBaseLat = currentLat;
        _stillBaseLng = currentLng;
      }
      return;
    }

    // ── C) GPS丢失时的特殊处理 ──
    if (gpsLost) {
      // GPS丢失时不主动降级，保持当前状态
      // 由累计位移兜底来判断是否仍在移动
      return;
    }

    // ── D) 低速度状态（GPS有信号但速度低） ──
    final bool isLowSpeed = speed != null && speed <= AppConfig.stationarySpeedThreshold;
    final bool isNoAccel = !_personMoving;
    final bool isSmallDisplacement = cumulativeDisplacement < AppConfig.cumulativeStillThreshold;

    if (isLowSpeed && isNoAccel && isSmallDisplacement) {
      // 三条件同时满足 → 可能进入静止
      if (_state == MotionState.moving) {
        // 记录低速度开始时间
        _lowSpeedStartTime ??= now;

        final elapsed = now.difference(_lowSpeedStartTime!).inSeconds;
        if (elapsed >= AppConfig.uncertainTriggerSec) {
          _transitionTo(MotionState.uncertain);
          _uncertainStartTime ??= now;
        }
      } else if (_state == MotionState.uncertain) {
        // 已在UNCERTAIN → 检查是否可以进入STATIONARY
        final elapsed = now.difference(_uncertainStartTime ?? now).inSeconds;
        if (elapsed >= AppConfig.uncertainToStationarySec) {
          _transitionTo(MotionState.stationary);
          _stillStartTime ??= now;
        }
      }
      // STATIONARY 已满足就保持
    } else {
      // 任一条件打破 → 回到MOVING
      if (_state != MotionState.moving) {
        _transitionTo(MotionState.moving);
      }
      _lowSpeedStartTime = null;
      _uncertainStartTime = null;

      // 更新静止基准点
      if (currentLat != null && currentLng != null) {
        _stillBaseLat = currentLat;
        _stillBaseLng = currentLng;
      }
    }
  }

  /// 更新静止基准点（强制重置累计位移）
  void resetStillBase(double lat, double lng) {
    _stillBaseLat = lat;
    _stillBaseLng = lng;
  }

  /// 获取静止基准点
  double? get stillBaseLat => _stillBaseLat;
  double? get stillBaseLng => _stillBaseLng;

  /// 计算累计位移（米）
  double calculateDisplacement(double currentLat, double currentLng) {
    if (_stillBaseLat == null || _stillBaseLng == null) {
      _stillBaseLat = currentLat;
      _stillBaseLng = currentLng;
      return 0.0;
    }
    return _haversineMeters(
      _stillBaseLat!, _stillBaseLng!,
      currentLat, currentLng,
    );
  }

  // ============================================================
  //  状态切换
  // ============================================================

  void _transitionTo(MotionState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(newState);
    }
  }

  // ============================================================
  //  工具
  // ============================================================

  double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    return haversineMeters(lat1, lng1, lat2, lng2);
  }

  /// 获取状态名
  String get stateName {
    switch (_state) {
      case MotionState.moving:
        return '移动中';
      case MotionState.uncertain:
        return '不确定';
      case MotionState.stationary:
        return '静止';
    }
  }
}
