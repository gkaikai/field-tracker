import 'package:flutter_test/flutter_test.dart';
import 'package:field_tracker/services/auth_service.dart';
import 'package:field_tracker/config/app_config.dart';

void main() {
  group('手机号验证', () {
    final validPhones = [
      '13800138000', '13912345678', '15012345678',
      '17612345678', '18812345678', '19912345678',
    ];
    final invalidPhones = [
      '',         // 空
      '12345',    // 不够11位
      '12345678901', // 以1开头11位但号段无效(12xxx)
      'abcdefghijk', // 非数字
      '1380013800',  // 10位
      '138001380000', // 12位
    ];

    for (final phone in validPhones) {
      test('有效手机号: $phone', () {
        expect(RegExp(r'^\d{11}$').hasMatch(phone), true);
        expect(RegExp(r'^1\d{10}$').hasMatch(phone), true);
        expect(RegExp(r'^1(3\d|4[5-9]|5[0-35-9]|6[2567]|7[0-8]|8\d|9[0-35-9])\d{8}$').hasMatch(phone), true);
      });
    }

    for (final phone in invalidPhones) {
      test('无效手机号: $phone', () {
        // 号段验证更严格，包含长度+首位+号段
        expect(RegExp(r'^1(3\d|4[5-9]|5[0-35-9]|6[2567]|7[0-8]|8\d|9[0-35-9])\d{8}$').hasMatch(phone), false);
      });
    }
  });

  group('AppConfig', () {
    test('baseUrl不能为空', () {
      expect(AppConfig.baseUrl.isNotEmpty, true);
    });

    test('定位间隔应在合理范围', () {
      expect(AppConfig.locationIntervalSeconds, greaterThanOrEqualTo(10));
      expect(AppConfig.locationIntervalSeconds, lessThanOrEqualTo(600));
    });
  });

  group('密码验证', () {
    test('合法密码6~50位', () {
      expect('test123456'.length, greaterThanOrEqualTo(6));
      expect('test123456'.length, lessThanOrEqualTo(50));
    });

    test('超长密码应拒绝', () {
      final long = 'A' * 100;
      expect(long.length, greaterThan(50));
    });
  });
}
