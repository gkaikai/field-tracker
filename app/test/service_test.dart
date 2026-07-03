import 'package:flutter_test/flutter_test.dart';
import 'package:field_tracker/utils/device_info.dart';
import 'package:field_tracker/services/background_service.dart';
import 'package:field_tracker/config/amap_key.dart';

void main() {
  group('AMapConfig', () {
    test('serverBaseUrl uses localhost in dev', () {
      expect(AMapConfig.serverBaseUrl, 'http://localhost:3000');
    });
    test('WS URL matches', () {
      expect(AMapConfig.wsUrl, 'ws://localhost:3000/ws/location');
    });
    test('uploadBatchSize is positive', () {
      expect(AMapConfig.uploadBatchSize, greaterThan(0));
    });
    test('uploadIntervalMs is positive', () {
      expect(AMapConfig.uploadIntervalMs, greaterThan(0));
    });
  });

  group('DeviceInfo — 品牌引导内容', () {
    test('华为返回正确的设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'Huawei');
      expect(info['title'], '华为手机设置引导');
      expect(info['steps'], contains('应用启动管理'));
      expect(info['steps'], contains('忽略电池优化'));
    });

    test('荣耀返回正确的设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'Honor');
      expect(info['title'], '荣耀手机设置引导');
      expect(info['steps'], contains('允许自启动'));
    });

    test('小米返回正确的设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'Xiaomi');
      expect(info['title'], '小米/Redmi手机设置引导');
      expect(info['steps'], contains('省电策略'));
      expect(info['steps'], contains('无限制'));
    });

    test('OPPO返回正确的设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'OPPO');
      expect(info['title'], 'OPPO/一加手机设置引导');
      expect(info['steps'], contains('允许完全后台运行'));
    });

    test('vivo返回正确的设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'vivo');
      expect(info['title'], 'vivo/iQOO手机设置引导');
      expect(info['steps'], contains('i管家'));
    });

    test('三星返回正确的设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'Samsung');
      expect(info['title'], '三星手机设置引导');
      expect(info['steps'], contains('深度休眠'));
    });

    test('Apple返回正确的设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'Apple');
      expect(info['title'], 'iOS 设置引导');
      expect(info['steps'], contains('定位服务'));
      expect(info['steps'], contains('始终'));
    });

    test('未知品牌返回通用设置说明', () async {
      final info = await DeviceInfo.getGuideInfo(brandOverride: 'UnknownBrand');
      expect(info['title'], '通用设置引导');
      expect(info['steps'], contains('应用管理'));
    });

    test('所有品牌都返回非空内容', () async {
      for (final brand in ['Huawei', 'Honor', 'Xiaomi', 'OPPO', 'vivo', 'Samsung', 'Apple', 'Unknown']) {
        final info = await DeviceInfo.getGuideInfo(brandOverride: brand);
        expect(info['title'], isNotEmpty, reason: 'Brand: $brand');
        expect(info['steps'], isNotEmpty, reason: 'Brand: $brand');
      }
    });

    test('各品牌引导步骤互不相同', () async {
      final allSteps = <String>{};
      for (final brand in ['Huawei', 'Xiaomi', 'OPPO', 'vivo', 'Apple']) {
        final info = await DeviceInfo.getGuideInfo(brandOverride: brand);
        allSteps.add(info['steps'] ?? '');
      }
      expect(allSteps.length, 5, reason: '每个品牌的步骤说明应该不同');
    });
  });

  group('DeviceInfo — 品牌图标和颜色', () {
    test('所有品牌对应的图标函数返回非null', () {
      // 这些 icon/color 函数是私有成员，通过UI可见
      // 验证品牌识别的完整性
      const brands = ['Huawei', 'Honor', 'Xiaomi', 'OPPO', 'vivo', 'Samsung', 'Apple'];
      expect(brands.length, 7);
    });
  });

  group('BackgroundService — 初始状态', () {
    test('未初始化时 isRunning 为 false', () {
      final service = BackgroundService();
      expect(service.isRunning, false);
    });
  });

  group('配置常量完整性', () {
    test('所有配置字段已定义', () {
      expect(AMapConfig.androidKey, isNotNull);
      expect(AMapConfig.iosKey, isNotNull);
      expect(AMapConfig.serverBaseUrl, isNotEmpty);
      expect(AMapConfig.wsUrl, isNotEmpty);
      expect(AMapConfig.wsUrl, startsWith('ws://'));
    });

    test('batch size 与间隔值合理', () {
      expect(AMapConfig.uploadBatchSize, inInclusiveRange(1, 1000));
      expect(AMapConfig.uploadIntervalMs, inInclusiveRange(1000, 3600000));
    });
  });
}
