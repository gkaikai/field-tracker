// 权限引导页 v2
import 'package:flutter/material.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});
  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  String _brand = '小米';

  @override
  Widget build(BuildContext context) {
    final brands = ['华为', '小米', 'OPPO', 'vivo', '荣耀', '三星', 'Apple'];
    return Scaffold(
      appBar: AppBar(title: Text('权限设置引导 · $_brand')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              const Icon(Icons.smartphone, size: 48, color: Color(0xFF2563EB)),
              const SizedBox(height: 12),
              const Text('后台运行权限', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('请允许APP在后台持续运行，以保证定位服务正常工作', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: brands.map((b) => GestureDetector(
                onTap: () => setState(() => _brand = b),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _brand == b ? const Color(0xFF2563EB) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _brand == b ? const Color(0xFF2563EB) : Colors.grey.shade300),
                  ),
                  child: Text(b, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                    color: _brand == b ? Colors.white : Colors.grey.shade700)),
                ),
              )).toList()),
            ]),
          ),
          const SizedBox(height: 20),
          _buildGuide(),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_circle),
            label: const Text('已完成设置'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
          )),
        ]),
      ),
    );
  }

  Widget _buildGuide() {
    final steps = {
      '小米': ['打开【设置】', '进入【应用设置】→【应用管理】', '找到【外勤定位】', '开启【自启动】', '进入【省电策略】→ 选择【无限制】', '返回桌面，长按APP图标→【锁住】'],
      '华为': ['打开【设置】', '搜索【启动管理】', '找到【外勤定位】', '关闭【自动管理】，开启【允许自启动】【允许关联启动】【允许后台活动】'],
      'OPPO': ['打开【设置】', '进入【应用管理】', '找到【外勤定位】', '开启【自启动】', '进入【耗电管理】→ 选择【无限制】'],
      'vivo': ['打开【i管家】', '进入【电池管理】→【耗电管理】', '找到【外勤定位】→ 选择【允许高耗电】', '返回【软件管理】→【自启动管理】→ 开启'],
      'Apple': ['打开【设置】', '进入【隐私】→【定位服务】', '找到【外勤定位】→ 选择【始终】', '返回【设置】→【通用】→【后台App刷新】→ 开启'],
    };
    final s = steps[_brand] ?? steps['小米']!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shield, color: Colors.white, size: 18)),
          const SizedBox(width: 8),
          Text('$_brand 设置步骤', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        ...List.generate(s.length, (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 20, height: 20, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), shape: BoxShape.circle),
              child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2563EB))))),
            const SizedBox(width: 8),
            Expanded(child: Text(s[i], style: const TextStyle(fontSize: 13))),
          ]),
        )),
      ]),
    );
  }
}
