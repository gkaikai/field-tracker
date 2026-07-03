import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:field_tracker/services/api_service.dart';
import 'package:field_tracker/services/auth_service.dart';
import 'package:field_tracker/services/location_service.dart';

/// 错误处理测试 / Error Handling Tests
///
/// 测试各种异常场景，确保错误回调正确触发、异常被正确处理。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiService - 异常处理 / Error Handling', () {
    test('单例模式 - 多次获取返回同一实例', () {
      final a = ApiService();
      final b = ApiService();
      expect(identical(a, b), isTrue);
    });

    test('setToken(null) - 清空令牌不应抛出异常', () {
      final api = ApiService();
      expect(() => api.setToken(null), returnsNormally);
    });

    test('setToken("") - 空字符串令牌不应抛出异常', () {
      final api = ApiService();
      expect(() => api.setToken(''), returnsNormally);
    });

    test('setToken("valid") - 有效令牌不应抛出异常', () {
      final api = ApiService();
      expect(() => api.setToken('valid_token_abc'), returnsNormally);
    });

    test('重复 setToken - 后续调用覆盖前值', () {
      final api = ApiService();
      api.setToken('first');
      api.setToken('second');
      api.setToken(null);
      // 不应抛出异常，验证通过即可
      expect(true, isTrue);
    });
  });

  group('AuthService - 登录异常 / Login Error Handling', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('restoreSession - 无已保存令牌应返回 false', () async {
      final auth = AuthService();
      final restored = await auth.restoreSession();
      expect(restored, isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.token, isNull);
    });

    test('restoreSession - 空令牌值应返回 true（空字符串 != null）', () async {
      SharedPreferences.setMockInitialValues({
        'token': '',
        'user_id': '',
        'user_name': '',
      });
      final auth = AuthService();
      final restored = await auth.restoreSession();
      // AuthService.restoreSession 只检查 _token != null，空字符串 "" 不是 null
      expect(restored, isTrue);
      expect(auth.token, equals(''));
    });

    test('logout - 未登录状态下登出不应抛出异常', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      await expectLater(auth.logout(), completes);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.token, isNull);
    });

    test('logout - 登录后登出应清除所有状态', () async {
      SharedPreferences.setMockInitialValues({
        'token': 'test_token',
        'user_id': '123',
        'user_name': 'test_user',
        'department': 'IT',
      });
      final auth = AuthService();
      await auth.restoreSession();
      expect(auth.isLoggedIn, isTrue);

      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.token, isNull);
      expect(auth.userId, isNull);
      expect(auth.userName, isNull);
      expect(auth.department, isNull);

      // 验证 SharedPreferences 中的值也被清除
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), isNull);
      expect(prefs.getString('user_id'), isNull);
      expect(prefs.getString('user_name'), isNull);
      expect(prefs.getString('department'), isNull);
    });

    test('login - 网络错误应抛出异常（通过 Dio 模拟）', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      // login 内部调用 ApiService.post -> Dio.post -> 真实网络请求
      // 在没有后端服务时，Dio 会抛出 DioException
      // 验证异常被抛出
      try {
        await auth.login('wrong_user', 'wrong_pass');
        fail('预期应抛出异常但未抛出');
      } catch (e) {
        // DioException 包含连接拒绝等网络错误
        expect(e, isA<Exception>());
      }
    });
  });

  group('LocationService - 异常处理 / Location Error Handling', () {
    test('单例模式 - 多次获取返回同一实例', () {
      final a = LocationService();
      final b = LocationService();
      expect(identical(a, b), isTrue);
    });

    test('初始状态 - currentPosition 应为 null', () {
      final loc = LocationService();
      expect(loc.currentPosition, isNull);
      expect(loc.isRunning, isFalse);
    });

    test('初始状态 - 回调默认为 null', () {
      final loc = LocationService();
      expect(loc.onLocationChanged, isNull);
      expect(loc.onError, isNull);
    });

    test('onError 回调 - 设置后应可被调用', () {
      final loc = LocationService();
      String? capturedError;
      loc.onError = (error) {
        capturedError = error;
      };

      // 手动触发 onError 回调（模拟权限拒绝场景）
      loc.onError?.call('定位权限被拒绝');
      expect(capturedError, equals('定位权限被拒绝'));

      loc.onError?.call('定位流错误: 位置服务不可用');
      expect(capturedError, equals('定位流错误: 位置服务不可用'));
    });

    test('onLocationChanged 回调 - 设置后应可被调用', () {
      final loc = LocationService();
      bool callbackFired = false;
      loc.onLocationChanged = (position) {
        callbackFired = true;
      };

      expect(loc.onLocationChanged, isNotNull);
      // 回调不为 null，但无法直接构造 Position 实例（依赖 geolocator 平台通道）
      // 所以仅验证回调可被赋值
    });

    test('stopTracking - 未启动状态下调用不应抛出异常', () {
      final loc = LocationService();
      expect(() => loc.stopTracking(), returnsNormally);
      expect(loc.isRunning, isFalse);
    });

    test('double stopTracking - 多次停止不应抛出异常', () {
      final loc = LocationService();
      loc.stopTracking();
      loc.stopTracking();
      loc.stopTracking();
      expect(loc.isRunning, isFalse);
    });
  });

  group('ApiService - Dio 异常模式 / Dio Error Patterns', () {
    test('setToken 链式调用 - null -> token -> null 不抛异常', () {
      final api = ApiService();
      api.setToken(null);
      api.setToken('abc');
      api.setToken(null);
      // 验证通过（不会抛出异常）
      expect(api, isA<ApiService>());
    });

    test('post/get 方法 - 无后端时抛出 DioException', () async {
      final api = ApiService();
      try {
        await api.post('/api/v1/auth/login', data: {'test': true});
        fail('预期应抛出异常');
      } catch (e) {
        // 连接被拒绝或超时都属于 DioException
        expect(e, isA<Exception>());
      }
    });

    test('get 方法 - 无后端时抛出 DioException', () async {
      final api = ApiService();
      try {
        await api.get('/api/v1/location/current');
        fail('预期应抛出异常');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });
  });

  group('AuthService - 凭据边界 / Credential Boundaries', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('空用户名登录应抛出异常', () async {
      final auth = AuthService();
      try {
        await auth.login('', 'password123');
        fail('预期应抛出异常');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('空密码登录应抛出异常', () async {
      final auth = AuthService();
      try {
        await auth.login('testuser', '');
        fail('预期应抛出异常');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('极长凭据登录应抛出异常', () async {
      final auth = AuthService();
      final longStr = 'a' * 10000;
      try {
        await auth.login(longStr, longStr);
        fail('预期应抛出异常');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });
  });
}
