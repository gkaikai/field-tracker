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

  // 完成状态
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
                  buttonText: '前往设置',
                  onTap: () async {
                    await SystemSettings.openAppSettings();
                    setState(() => _locationDone = true);
                    _checkAllDone();
                  },
                ),
                const SizedBox(height: 12),

                // ── 步骤2：忽略电池优化 ──
                _buildStepCard(
                  icon: Icons.battery_charging_full,
                  title: '忽略电池优化',
                  subtitle: '防止系统在后台时自动关闭APP定位',
                  done: _batteryDone,
                  buttonText: '前往设置',
                  onTap: () async {
                    await SystemSettings.requestBatteryOptimization();
                    setState(() => _batteryDone = true);
                    _checkAllDone();
                  },
                ),
                const SizedBox(height: 12),

                // ── 步骤3：后台运行权限 ──
                _buildStepCard(
                  icon: Icons.settings,
                  title: '允许后台运行',
                  subtitle: _getBrandBgHint(_brand),
                  done: _bgDone,
                  buttonText: '前往设置',
                  onTap: () async {
                    await SystemSettings.openAppSettings();
                    setState(() => _bgDone = true);
                    _checkAllDone();
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
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: done ? 1 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(buttonText, style: const TextStyle(fontSize: 12)),
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
    switch (brand) {
      case 'Huawei':
        return {
          'title': '华为额外设置',
          'steps': '进入「设置→应用→应用管理→本应用→耗电详情」，关闭「自动管理」，手动开启三项权限。',
        };
      case 'Xiaomi':
        return {
          'title': '小米额外设置',
          'steps': '进入「设置→应用设置→应用管理→本应用→省电策略」，选择「无限制」。同时开启「自启动」。',
        };
      case 'OPPO':
        return {
          'title': 'OPPO额外设置',
          'steps': '进入「设置→应用→应用管理→本应用→耗电管理」，开启「允许完全后台运行」。',
        };
      default:
        return null;
    }
  }

  String _getBrandBgHint(String brand) {
    switch (brand) {
      case 'Huawei':
        return '在应用详情中关闭「自动管理」并开启后台活动';
      case 'Xiaomi':
        return '在应用详情中将省电策略设为「无限制」';
      case 'OPPO':
        return '在应用详情中开启「允许完全后台运行」';
      default:
        return '在应用详情中允许后台运行';
    }
  }

  bool _allDone() => _locationDone && _batteryDone && _bgDone;

  void _checkAllDone() {
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

  Future<void> _onDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('background_guide_done', true);
      await prefs.setString('device_brand', _brand);
    } catch (e) {
      debugPrint('[PermissionGuide] 保存设置失败: $e');
    }

    if (mounted) {
      if (_allDone()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置完成，感谢配合！'),
            backgroundColor: Colors.green,
          ),
        );
      }
      Navigator.pop(context);
    }
  }
}
