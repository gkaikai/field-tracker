import 'package:flutter_test/flutter_test.dart';
import 'package:field_tracker/services/api_service.dart';

void main() {
  group('ApiService', () {
    test('should be a singleton', () {
      final instance1 = ApiService();
      final instance2 = ApiService();
      expect(identical(instance1, instance2), true);
    });

    test('setToken should accept null (clear token)', () {
      final api = ApiService();
      expect(() => api.setToken(null), returnsNormally);
    });

    test('setToken should accept empty string', () {
      final api = ApiService();
      expect(() => api.setToken(''), returnsNormally);
    });

    test('setToken should accept valid token', () {
      final api = ApiService();
      expect(() => api.setToken('test_token_123'), returnsNormally);
    });
  });
}
