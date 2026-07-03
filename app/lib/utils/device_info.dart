/// 设备信息工具 - 识别手机品牌用于显示对应的后台权限引导
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

class DeviceInfo {
  static final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  /// 获取设备品牌（华为/小米/OPPO/vivo/Samsung/Apple/其他）
  static Future<String> getBrand() async {
    if (Platform.isIOS) return 'Apple';
    if (Platform.isAndroid) {
      try {
        final info = await _plugin.androidInfo;
        final brand = info.brand.toLowerCase();

        if (brand.contains('huawei') || brand.contains('honor')) {
          // 进一步区分华为和荣耀
          if (brand.contains('honor')) return 'Honor';
          return 'Huawei';
        }
        if (brand.contains('xiaomi') ||
            brand.contains('redmi') ||
            brand.contains('poco')) { return 'Xiaomi'; }
        if (brand.contains('oppo') || brand.contains('oneplus')) return 'OPPO';
        if (brand.contains('vivo') || brand.contains('iqoo')) return 'vivo';
        if (brand.contains('samsung')) return 'Samsung';
        if (brand.contains('meizu')) return 'Meizu';
        return brand;
      } catch (_) {
        return 'Android';
      }
    }
    return 'Unknown';
  }

  /// 是否需要显示后台保活引导
  /// iOS 不需要额外引导，国产 Android ROM 需要
  static Future<bool> needsWhitelistGuide() async {
    if (Platform.isIOS) return false;
    final brand = await getBrand();
    const chinaBrands = [
      'Huawei', 'Honor', 'Xiaomi', 'OPPO', 'vivo',
      'Meizu', 'OnePlus'
    ];
    return chinaBrands.contains(brand);
  }

  /// 获取对应品牌的引导说明文案
  /// [brandOverride] — 测试用，传入品牌名跳过 getBrand() 调用
  static Future<Map<String, String>> getGuideInfo({String? brandOverride}) async {
    final brand = brandOverride ?? await getBrand();

    switch (brand) {
      case 'Huawei':
        return {
          'title': '华为手机设置引导',
          'steps': '''
1. 打开「设置」→「应用」→「应用管理」
2. 找到本应用「Field Tracker」
3. 点击「耗电详情」→ 关闭「应用启动管理」的「自动管理」
4. 在弹出的窗口中，开启「允许自启动」「允许关联启动」「允许后台活动」
5. 返回设置 → 搜索「忽略电池优化」→ 允许本应用
''',
        };
      case 'Honor':
        return {
          'title': '荣耀手机设置引导',
          'steps': '''
1. 打开「设置」→「应用」→「应用管理」
2. 找到本应用「Field Tracker」
3. 点击「耗电详情」→ 关闭「应用启动管理」的「自动管理」
4. 开启「允许自启动」「允许关联启动」「允许后台活动」
5. 返回「设置」→「电池」→ 关闭「智能充电模式」（可选）
''',
        };
      case 'Xiaomi':
        return {
          'title': '小米/Redmi手机设置引导',
          'steps': '''
1. 打开「设置」→「应用设置」→「应用管理」
2. 找到本应用「Field Tracker」
3. 点击「省电策略」→ 选择「无限制」
4. 开启「自启动」
5. 返回「设置」→「电池与性能」→「应用智能省电」
6. 找到本应用，设置为「无限制」
7. 打开「最近任务」界面，将本应用下拉锁定（加锁图标）
''',
        };
      case 'OPPO':
        return {
          'title': 'OPPO/一加手机设置引导',
          'steps': '''
1. 打开「设置」→「应用」→「应用管理」
2. 找到本应用「Field Tracker」
3. 点击「耗电管理」→ 开启「允许完全后台运行」
4. 开启「自启动」
5. 返回「设置」→「电池」→「应用耗电管理」
6. 找到本应用，选择「允许完全后台运行」
7. 打开「最近任务」界面，将本应用下拉锁定
''',
        };
      case 'vivo':
        return {
          'title': 'vivo/iQOO手机设置引导',
          'steps': '''
1. 打开「i管家」→「电池管理」→「后台高耗电」
2. 找到本应用「Field Tracker」，开启开关
3. 返回「i管家」→「应用管理」→「自启动管理」
4. 开启本应用的自启动权限
5. 打开「设置」→「电池」→ 关闭「后台高耗电提醒」
6. 打开「最近任务」界面，将本应用下拉锁定
''',
        };
      case 'Samsung':
        return {
          'title': '三星手机设置引导',
          'steps': '''
1. 打开「设置」→「电池」→「后台使用限制」
2. 找到本应用「Field Tracker」→ 关闭「让应用程序进入深度休眠」
3. 打开「设置」→「应用程序」→ 找到本应用 →「电池」
4. 选择「不受限制」
5. 打开「最近任务」界面，点击本应用图标 → 锁定应用
''',
        };
      case 'Apple':
        return {
          'title': 'iOS 设置引导',
          'steps': '''
1. 打开「设置」→「隐私与安全性」→「定位服务」
2. 找到本应用「Field Tracker」
3. 选择「始终」
4. 开启「精确位置」
''',
        };
      default:
        return {
          'title': '通用设置引导',
          'steps': '''
1. 打开「设置」→「应用管理」
2. 找到本应用「Field Tracker」
3. 关闭「省电优化」或「智能限制」
4. 开启「自启动」
5. 允许「后台运行」「忽略电池优化」
''',
        };
    }
  }
}
