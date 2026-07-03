import 'package:flutter_test/flutter_test.dart';
import 'dart:io' show Platform;

void main() {
  group('平台兼容性测试 - Platform Detection', () {
    test('Platform.isAndroid should be boolean', () {
      // 平台检测不应抛出异常
      expect(() => Platform.isAndroid, returnsNormally);
      expect(Platform.isAndroid, isA<bool>());
    });

    test('Platform.isIOS should be boolean', () {
      expect(() => Platform.isIOS, returnsNormally);
      expect(Platform.isIOS, isA<bool>());
    });

    test('Platform.operatingSystem should return a valid value', () {
      expect(Platform.operatingSystem, isA<String>());
      expect(Platform.operatingSystem, isNotEmpty);
    });

    test('Platform.isMacOS should be available', () {
      expect(() => Platform.isMacOS, returnsNormally);
    });
  });
}
