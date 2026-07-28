// 权限引导页 — 一键跳转系统设置
//
// 第一次安装打开时自动弹出，每个步骤带"前往设置"按钮，
// 一点直接跳到对应的系统设置页面，用户只需点开关即可。

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_info.dart';
import '../utils/system_settings.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  String _brand = '检测中...';
  bool _loading = true;

  // 已跳转到系统设置（第一步）
  bool _locationJumped = false;
  bool _batteryJumped = false;
  bool _bgJumped = false;

  // 用户手动确认已完成（第二步）
  bool _locationDone = false;
  bool _batteryDone = false;
  bool _bgDone = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final brand = await DeviceInfo.getBrand();
      setState(() {
        _brand = brand;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[PermissionGuide] 检测设备信息失败: $e');
      setState(() {
        _brand = '未知';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('权限设置引导 · $_brand'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 顶部说明
                const Center(
                  child: Icon(Icons.handyman, size: 48, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '完成以下设置，APP才能后台持续定位',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 24),

                // ── 步骤1：定位权限 ──
                _buildStepCard(
                  icon: Icons.my_location,
                  title: '允许定位权限',
                  subtitle: '用于实时追踪您的当前位置',
                  done: _locationDone,
                  jumped: _locationJumped,
                  onTap: () async {
                    if (_locationDone) return;
                    if (_locationJumped) {
                      setState(() => _locationDone = true);
                      _checkAllDone();
                      return;
                    }
                    final success = await SystemSettings.openAppSettings();
                    if (!success) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('跳转失败，请手动在系统设置中开启定位权限'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    if (!context.mounted) return;
                    setState(() => _locationJumped = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('设置后点「✅ 点此确认已设置」'),
                        duration: Duration(seconds: 4),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // ── 步骤2：忽略电池优化 ──
                _buildStepCard(
                  icon: Icons.battery_charging_full,
                  title: '忽略电池优化',
                  subtitle: '手动关闭电池优化防止系统后台杀定位',
                  done: _batteryDone,
                  jumped: _batteryJumped,
                  onTap: () async {
                    if (_batteryDone) return;
                    if (_batteryJumped) {
                      setState(() => _batteryDone = true);
                      _checkAllDone();
                      return;
                    }
                    final success = await SystemSettings.requestBatteryOptimization();
                    if (!success) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('跳转失败，请手动在系统设置中关闭电池优化'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    if (!context.mounted) return;
                    setState(() => _batteryJumped = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('关闭${_getBrandBatteryTerm(_brand)}后点「✅ 点此确认已设置」'),
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // ── 步骤3：后台运行权限 ──
                _buildStepCard(
                  icon: Icons.settings,
                  title: '允许后台运行',
                  subtitle: _getBrandBgHint(_brand),
                  done: _bgDone,
                  jumped: _bgJumped,
                  onTap: () async {
                    if (_bgDone) return;
                    if (_bgJumped) {
                      setState(() => _bgDone = true);
                      _checkAllDone();
                      return;
                    }
                    final success = await SystemSettings.openAppSettings();
                    if (!success) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('跳转失败，请手动在系统设置中允许后台运行'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    if (!context.mounted) return;
                    setState(() => _bgJumped = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('开启后台运行后点「✅ 点此确认已设置」'),
                        duration: Duration(seconds: 4),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // ── 额外：分品牌说明 ──
                _buildBrandGuide(_brand),
                const SizedBox(height: 24),

                // ── 完成按钮 ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _onDone,
                    icon: Icon(
                      Icons.check_circle,
                      color: _allDone() ? Colors.white : Colors.grey[400],
                    ),
                    label: Text(
                      _allDone() ? '全部完成，开始使用' : '稍后再说',
                      style: TextStyle(
                        fontSize: 16,
                        color: _allDone() ? Colors.white : Colors.grey[600],
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _allDone() ? Colors.green : Colors.grey[200],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('跳过', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStepCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool done,
    required bool jumped,
    required VoidCallback onTap,
  }) {
    final btnText = done ? '✅ 已设置' : (jumped ? '✅ 点此确认已设置' : '前往设置');
    return Card(
      elevation: done ? 1 : (jumped ? 3 : 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: jumped && !done
            ? BorderSide(color: Colors.green[200]!, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: done ? Colors.green[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: done ? Colors.green : Colors.blue[700], size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: done ? Colors.green[700] : null)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            if (done)
              const Icon(Icons.check_circle, color: Colors.green, size: 24)
            else
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  backgroundColor: jumped ? Colors.green[50] : Colors.blue[50],
                  foregroundColor: jumped ? Colors.green[700] : Colors.blue[700],
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(btnText, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandGuide(String brand) {
    final guide = _getBrandGuideMap(brand);
    if (guide == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[200]!),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber[700], size: 18),
              const SizedBox(width: 8),
              Text(guide['title']!,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.amber[900])),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            guide['steps']!,
            style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.6),
          ),
        ],
      ),
    );
  }

  Map<String, String>? _getBrandGuideMap(String brand) {
    switch (brand.toLowerCase()) {
      case 'huawei':
        return {
          'title': '华为额外设置',
          'steps': '进入「设置→应用→应用管理→本应用→耗电详情」，关闭「自动管理」，手动开启三项权限。',
        };
      case 'xiaomi':
        return {
          'title': '小米额外设置',
          'steps': '进入「设置→应用设置→应用管理→本应用→省电策略」，选择「无限制」。同时开启「自启动」。',
        };
      case 'oppo':
        return {
          'title': 'OPPO额外设置',
          'steps': '进入「设置→应用→应用管理→本应用→耗电管理」，开启「允许完全后台运行」。',
        };
      default:
        return null;
    }
  }

  String _getBrandBgHint(String brand) {
    switch (brand.toLowerCase()) {
      case 'huawei':
        return '在应用详情中关闭「自动管理」并开启后台活动';
      case 'xiaomi':
        return '在应用详情中将省电策略设为「无限制」';
      case 'oppo':
        return '在应用详情中开启「允许完全后台运行」';
      default:
        return '在应用详情中允许后台运行';
    }
  }

  /// 电池优化在不同品牌ROM上的术语
  String _getBrandBatteryTerm(String brand) {
    switch (brand.toLowerCase()) {
      case 'huawei':
      case 'oppo':
        return '「耗电管理」';
      case 'xiaomi':
        return '「省电策略」';
      case 'vivo':
        return '「后台高耗电」';
      case 'samsung':
        return '「后台使用限制」';
      default:
        return '电池优化';
    }
  }

  bool _allDone() => _locationDone && _batteryDone && _bgDone;

  void _checkAllDone() {
    if (!mounted) return;
    if (_allDone()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('所有权限已设置完成！'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
    setState(() {});
  }

  bool _onDoneGuard = false;

  Future<void> _onDone() async {
    if (_onDoneGuard) return;
    _onDoneGuard = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('background_guide_done', true);
      await prefs.setString('device_brand', _brand);
    } catch (e) {
      debugPrint('[PermissionGuide] 保存设置失败: $e');
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
