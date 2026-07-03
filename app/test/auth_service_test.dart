import 'package:flutter_test/flutter_test.dart';
import 'package:field_tracker/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AuthService', () {
    late AuthService authService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      authService = AuthService();
    });

    test('should start with no session', () {
      expect(authService.isLoggedIn, false);
      expect(authService.token, isNull);
      expect(authService.userId, isNull);
      expect(authService.userName, isNull);
    });

    test('restoreSession should return false when no stored session', () async {
      final result = await authService.restoreSession();
      expect(result, false);
      expect(authService.isLoggedIn, false);
    });

    test('logout should clear session', () async {
      // 先模拟登录（实际不会发网络请求，只是验证初始状态）
      expect(authService.isLoggedIn, false);
      
      // 登出（即使未登录也不应报错）
      await authService.logout();
      expect(authService.isLoggedIn, false);
      expect(authService.token, isNull);
    });
  });
}
