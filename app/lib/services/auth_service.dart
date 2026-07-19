import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'error_codes.dart';

/// 认证服务
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final ApiService _api = ApiService();
  String? _token;
  String? _userId;
  String? _userName;
  String? _department;
  String? _role;

  AuthService._internal();

  String? get token => _token;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get department => _department;
  String? get role => _role;
  bool get isLoggedIn => _token != null;

  /// 从本地恢复登录态
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _userId = prefs.getString('user_id');
    _userName = prefs.getString('user_name');
    _department = prefs.getString('department');
    _role = prefs.getString('role');
    if (_token != null) {
      _api.setToken(_token);
      return true;
    }
    return false;
  }

  /// 登录
  ///
  /// 返回用户数据 map（含 token、userId 等）。
  /// 业务错误码（10003 账号不存在、10004 密码错误、10005 账号锁定等）
  /// 由 ApiService 拦截器统一弹出 Toast，此处抛出 [ApiException] 供 UI 层判断。
  Future<Map<String, dynamic>> login(String phone, String password) async {
    try {
      final resp = await _api.post(AppConfig.apiLogin, data: {
        'phone': phone,
        'password': password,
      });

      final data = resp.data as Map<String, dynamic>;

      // 虽然拦截器已处理业务 code，但双重校验确保安全
      final int? bizCode = data['code'] as int?;
      if (bizCode != null && bizCode != 200 && ErrorCode.isBusinessError(bizCode)) {
        throw ApiException(
          code: bizCode,
          message: ErrorCode.message(bizCode),
          rawData: data,
        );
      }

      _token = data['token'] as String?;
      // 兼容两种返回格式：{user:{id:...}} 或 {userId:...}
      _userId = (data['user']?['id'] ?? data['userId'] ?? '').toString();
      _userName = (data['user']?['name'] ?? data['name'] as String?) ?? phone;
      _department = (data['user']?['department'] ?? data['departmentId'] as String?);
      _role = (data['user']?['role'] ?? data['role'] as String?)?.toString();

      if (_token != null) {
        _api.setToken(_token);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        await prefs.setString('user_id', _userId ?? '');
        await prefs.setString('user_name', _userName ?? '');
        if (_department != null) {
          await prefs.setString('department', _department!);
        }
        if (_role != null) {
          await prefs.setString('role', _role!);
        }
      }

      return data;
    } on DioException catch (e) {
      // 拦截器已抛出带 ApiException 的 DioException，提取后重抛
      if (e.error is ApiException) {
        rethrow;
      }
      // 网络异常等已在拦截器弹出 toast，此处统一抛 ApiException 避免 UI 层暴露技术细节
      throw ApiException(
        code: 10010,
        message: _networkMessage(e),
      );
    }
  }

  /// 登出
  Future<void> logout() async {
    _token = null;
    _userId = null;
    _userName = null;
    _department = null;
    _api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('department');
    await prefs.remove('role');
  }

  /// 将 DioException 映射为简单提示文案
  static String _networkMessage(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        '网络连接超时，请检查网络后重试',
      DioExceptionType.connectionError => '网络连接失败，请检查网络后重试',
      _ => '登录失败，请稍后重试',
    };
  }
}
