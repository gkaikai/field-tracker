import '../config/app_config.dart';
import 'api_service.dart';

/// 考勤打卡服务
class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  final ApiService _api = ApiService();

  /// 打卡签到/签退
  Future<Map<String, dynamic>> checkin({
    required String type,
    required double lng,
    required double lat,
    String? address,
    String? photoUrl,
    String? wifiBssid,
  }) async {
    final resp = await _api.post(AppConfig.apiCheckin, data: {
      'type': type,
      'lng': lng,
      'lat': lat,
      if (address != null) 'address': address,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (wifiBssid != null) 'wifi_bssid': wifiBssid,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// 获取打卡记录（分页）
  Future<Map<String, dynamic>> getRecords({
    int page = 1,
    int pageSize = 20,
    String? startDate,
    String? endDate,
    String? type,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'pageSize': pageSize,
    };
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;
    if (type != null) params['type'] = type;

    final resp = await _api.get(AppConfig.apiAttendanceRecords, query: params);
    return resp.data as Map<String, dynamic>;
  }
}
