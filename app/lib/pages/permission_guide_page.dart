// 国产ROM后台权限引导页
//
// 根据检测到的手机品牌，显示对应厂商的后台保活设置路径
// 用户在设置完成后点击"已完成"，标记权限已配置

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_info.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  String _brand = '检测中...';
  String _title = '';
  String _steps = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    final brand = await DeviceInfo.getBrand();
    final guide = await DeviceInfo.getGuideInfo();
    setState(() {
      _brand = brand;
      _title = guide['title'] ?? '';
      _steps = guide['steps'] ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('后台权限设置 · $_brand'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 品牌图标
                Center(
                  child: Icon(
                    _getBrandIcon(_brand),
                    size: 64,
                    color: _getBrandColor(_brand),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '检测到您的手机是 $_brand',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '为了在后台持续记录位置，请按以下步骤设置',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 24),

                // 设置步骤
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue[700], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _steps,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.8,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 提示信息
                Container(
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          color: Colors.amber[700], size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '不同系统版本界面可能略有差异，核心是保证应用在 "设置→应用管理→本应用" 中被允许后台运行且不被省电优化限制。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 已完成按钮
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _onDone,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('我已按以上步骤完成设置',
                        style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('稍后再说', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _onDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_guide_done', true);
    await prefs.setString('device_brand', _brand);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已记录，感谢配合！'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  IconData _getBrandIcon(String brand) {
    switch (brand) {
      case 'Huawei':
        return Icons.wifi_tethering;
      case 'Honor':
        return Icons.flare;
      case 'Xiaomi':
        return Icons.battery_charging_full;
      case 'OPPO':
        return Icons.power;
      case 'vivo':
        return Icons.phone_android;
      case 'Samsung':
        return Icons.star;
      case 'Apple':
        return Icons.apple;
      default:
        return Icons.smartphone;
    }
  }

  Color _getBrandColor(String brand) {
    switch (brand) {
      case 'Huawei':
        return const Color(0xFFCF0A2C);
      case 'Honor':
        return const Color(0xFF000000);
      case 'Xiaomi':
        return const Color(0xFFFF6900);
      case 'OPPO':
        return const Color(0xFF1A6B37);
      case 'vivo':
        return const Color(0xFF415FFF);
      default:
        return Colors.blue;
    }
  }
}
