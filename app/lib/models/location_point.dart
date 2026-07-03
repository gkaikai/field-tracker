/// 位置数据模型
class LocationPoint {
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracy;   // 精度(米)
  final double? speed;      // 速度(m/s)
  final double? altitude;   // 海拔(米)
  final double? bearing;    // 方向角(度)
  final double? battery;    // 电量(0~1)
  final DateTime timestamp;

  LocationPoint({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.altitude,
    this.bearing,
    this.battery,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 转为 JSON 上报
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'lng': longitude,
        'lat': latitude,
        'accuracy': accuracy,
        'speed': speed,
        'altitude': altitude,
        'bearing': bearing,
        'battery': battery,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LocationPoint.fromJson(Map<String, dynamic> json) =>
      LocationPoint(
        userId: json['userId'] ?? '',
        latitude: _toDouble(json['lat']) ?? 0,
        longitude: _toDouble(json['lng']) ?? 0,
        accuracy: _toDouble(json['accuracy'] as Object?),
        speed: _toDouble(json['speed'] as Object?),
        altitude: _toDouble(json['altitude'] as Object?),
        bearing: _toDouble(json['bearing'] as Object?),
        battery: _toDouble(json['battery'] as Object?),
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );

  /// 兼容 String 和 num 类型的数值转换
  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// SQLite 存储
  Map<String, dynamic> toDbMap() => {
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'speed': speed,
        'battery': battery,
        'recorded_at': timestamp.toIso8601String(),
        'uploaded': 0, // 0=未上传, 1=已上传
      };

  @override
  String toString() =>
      'LocationPoint(${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)})';
}
