import 'package:flutter_test/flutter_test.dart';
import 'package:field_tracker/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('baseUrl should be a valid URL', () {
      expect(AppConfig.baseUrl, startsWith('http'));
      final uri = Uri.tryParse(AppConfig.baseUrl);
      expect(uri, isNotNull);
      expect(uri!.host, isNotEmpty);
    });

    test('amapApiKey should not be empty', () {
      expect(AppConfig.amapApiKey, isNotEmpty);
    });

    test('locationIntervalSeconds should be reasonable', () {
      expect(AppConfig.locationIntervalSeconds, greaterThan(0));
      expect(AppConfig.locationIntervalSeconds, lessThanOrEqualTo(300));
    });

    test('notification channel config should be present', () {
      expect(AppConfig.notificationChannelId, isNotEmpty);
      expect(AppConfig.notificationChannelName, isNotEmpty);
    });

    test('API paths should be valid', () {
      expect(AppConfig.apiLogin, startsWith('/'));
      expect(AppConfig.apiReportLocation, startsWith('/'));
      expect(AppConfig.apiCurrentLocation, startsWith('/'));
      expect(AppConfig.apiBatchLocation, startsWith('/'));
      expect(AppConfig.apiTrack, startsWith('/'));
    });
  });
}
