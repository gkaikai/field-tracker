import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'api_service.dart';

/// 认证服务
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final ApiService _api = ApiService();
  String? _token;
  String? _userId;
  String? _userName;
  String? _department;

  AuthService._internal();

  String? get token => _token;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get department => _department;
  bool get isLoggedIn => _token != null;

  /// 从本地恢复登录态
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _userId = prefs.getString('user_id');
    _userName = prefs.getString('user_name');
    _department = prefs.getString('department');
    if (_token != null) {
      _api.setToken(_token);
      return true;
    }
    return false;
  }

  /// 登录
  Future<Map<String, dynamic>> login(String username, String password) async {
    final resp = await _api.post(AppConfig.apiLogin, data: {
      'username': username,
      'password': password,
    });

    final data = resp.data as Map<String, dynamic>;
    _token = data['token'] as String?;
    _userId = (data['user']?['id'] ?? '').toString();
    _userName = data['user']?['name'] as String? ?? username;
    _department = data['user']?['department'] as String?;

    if (_token != null) {
      _api.setToken(_token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      await prefs.setString('user_id', _userId ?? '');
      await prefs.setString('user_name', _userName ?? '');
      if (_department != null) {
        await prefs.setString('department', _department!);
      }
    }

    return data;
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
  }
}
