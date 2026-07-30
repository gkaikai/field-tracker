import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'error_codes.dart';
import 'app_role.dart';

/// 认证服务 — 单例，继承 ChangeNotifier 支持响应式监听
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final ApiService _api = ApiService();
  String? _token;
  String? _userId;
  String? _userCode;
  String? _userName;
  String? _department;
  String? _role;

  AuthService._internal();

  String? get token => _token;
  String? get userId => _userId;
  String? get userCode => _userCode;
  String? get userName => _userName;
  String? get department => _department;
  String? get role => _role;
  bool get isLoggedIn => _token != null;

  /// 使用 AppRole 枚举判断是否为管理角色（替代魔法字符串）
  bool get isAdmin => AppRole.isAdmin(_role);
  bool get isEmployee => _role == AppRole.employee;

  /// 从本地恢复登录态，并通过服务端验证Token有效性
  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      _userId = prefs.getString('user_id');
      _userCode = prefs.getString('user_code');
      _userName = prefs.getString('user_name');
      _department = prefs.getString('department');
      _role = prefs.getString('role');
      if (_token == null) return false;
      
      _api.setToken(_token);
      try {
        await _api.get('/api/v1/auth/me');
        notifyListeners();
        return true;
      } catch (_) {
        // Token无效，清除本地缓存
        _clearState();
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// 登录
  Future<Map<String, dynamic>> login(String phone, String password) async {
    try {
      final resp = await _api.post(AppConfig.apiLogin, data: {
        'phone': phone,
        'password': password,
      });

      final dynamic rawData = resp.data;
      final Map<String, dynamic>? data;
      if (rawData is Map<String, dynamic>) {
        data = rawData;
      } else {
        throw ApiException(
          code: 10010,
          message: '服务器返回格式异常',
        );
      }

      final int? bizCode = data['code'] as int?;
      if (bizCode != null && bizCode != 200 && ErrorCode.isBusinessError(bizCode)) {
        throw ApiException(
          code: bizCode,
          message: ErrorCode.message(bizCode),
          rawData: data,
        );
      }

      _token = data['token'] as String?;
      _userId = (data['user']?['id'] ?? data['userId'] ?? '').toString();
      _userCode = (data['user']?['userCode'] ?? data['userCode'] ?? '').toString();
      _userName = (data['user']?['name'] ?? data['name']?.toString()) ?? '用户';
      _department = (data['user']?['department'] ?? data['departmentId']?.toString());
      _role = (data['user']?['role'] ?? data['role']?.toString())?.toString();

      if (_token != null) {
        _api.setToken(_token);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        await prefs.setString('user_id', _userId ?? '');
        await prefs.setString('user_code', _userCode ?? '');
        await prefs.setString('user_name', _userName ?? '');
        if (_department != null) {
          await prefs.setString('department', _department!);
        }
        if (_role != null) {
          await prefs.setString('role', _role!);
        }
        notifyListeners();
      }

      return data;
    } on DioException catch (e) {
      if (e.error is ApiException) {
        rethrow;
      }
      throw ApiException(
        code: 10010,
        message: _networkMessage(e),
      );
    }
  }

  /// 登出
  Future<void> logout() async {
    _clearState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');
    await prefs.remove('user_code');
    await prefs.remove('user_name');
    await prefs.remove('department');
    await prefs.remove('role');
    notifyListeners();
  }

  /// 清除内存中的登录态
  void _clearState() {
    _token = null;
    _userId = null;
    _userCode = null;
    _userName = null;
    _department = null;
    _role = null;
    _api.setToken(null);
  }

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
