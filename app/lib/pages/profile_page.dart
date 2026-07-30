// 个人中心页面
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/amap_location_service.dart';
import '../services/background_location_service.dart';
import '../theme/app_theme.dart';
import 'permission_guide_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _auth = AuthService();
  final _oldPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool _loading = false;
  String? _msg;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  void _loadVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = '${pkg.version}+${pkg.buildNumber}');
    } catch (_) {
      // ignore: silently fall back to empty
    }
  }

  @override
  void dispose() {
    _oldPwdCtrl.dispose(); _newPwdCtrl.dispose(); _confirmPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_oldPwdCtrl.text.isEmpty || _newPwdCtrl.text.isEmpty) {
      setState(() => _msg = '请填写完整'); return;
    }
    if (_newPwdCtrl.text != _confirmPwdCtrl.text) {
      setState(() => _msg = '两次密码不一致'); return;
    }
    if (_newPwdCtrl.text.length < 6) {
      setState(() => _msg = '密码至少6位'); return;
    }
    setState(() => _loading = true);
    try {
      await ApiService().post('/api/v1/auth/change-password', data: {
        'oldPassword': _oldPwdCtrl.text, 'newPassword': _newPwdCtrl.text,
      });
      setState(() { _msg = '✅ 修改成功'; _oldPwdCtrl.clear(); _newPwdCtrl.clear(); _confirmPwdCtrl.clear(); });
    } catch (e) {
      setState(() => _msg = '❌ 修改失败: $e');
    } finally { setState(() => _loading = false); }
  }

  void _showPasswordDialog() {
    _oldPwdCtrl.clear(); _newPwdCtrl.clear(); _confirmPwdCtrl.clear(); _msg = null;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_msg != null) Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _msg!.startsWith('✅') ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_msg!, style: TextStyle(fontSize: 13, color: _msg!.startsWith('✅') ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
          ),
          if (_msg != null) const SizedBox(height: 8),
          TextField(controller: _oldPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '原密码', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _newPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _confirmPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: _loading ? null : () async {
            if (_oldPwdCtrl.text.isEmpty || _newPwdCtrl.text.isEmpty) {
              setS(() => _msg = '请填写完整'); return;
            }
            if (_newPwdCtrl.text != _confirmPwdCtrl.text) { setS(() => _msg = '两次密码不一致'); return; }
            setS(() => _loading = true);
            try {
              await ApiService().post('/api/v1/auth/change-password', data: {
                'oldPassword': _oldPwdCtrl.text, 'newPassword': _newPwdCtrl.text,
              });
              setS(() { _msg = '✅ 修改成功'; _loading = false; });
              await Future.delayed(const Duration(seconds: 1));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              setS(() { _msg = '❌ 修改失败: $e'; _loading = false; });
            }
          }, child: Text(_loading ? '修改中...' : '确认修改')),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _auth.isAdmin;
    final primaryColor = isAdmin ? context.adminPrimary : theme.colorScheme.primary;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          // 用户信息头
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 20, bottom: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.2)),
                child: Center(child: Text(
                  (_auth.userName ?? '?').isNotEmpty ? _auth.userName![0] : '?',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                )),
              ),
              const SizedBox(height: 12),
              Text(_auth.userName ?? '未登录', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: Text(isAdmin ? '管理员' : '员工', style: const TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ]),
          ),

          // 设置列表
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _sectionTitle('账号设置'),
              _settingItem(context, Icons.lock_outline, '修改密码', onTap: _showPasswordDialog),
              _settingItem(context, Icons.phone_android, '后台权限引导', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PermissionGuidePage()))),
              const Divider(height: 32),
              _sectionTitle('数据与存储'),
              _settingItem(context, Icons.sync, '同步离线数据'),
              _settingItem(context, Icons.delete_outline, '清除缓存', subtitle: '12.5 MB'),
              const Divider(height: 32),
              _sectionTitle('关于'),
              _settingItem(context, Icons.info_outline, '版本', subtitle: 'v$_appVersion'),
              _settingItem(context, Icons.system_update, '检查更新'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(alignment: Alignment.centerLeft, child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
    ));
  }

  Widget _settingItem(BuildContext context, IconData icon, String title, {String? subtitle, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade600, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing: subtitle != null
          ? Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
          : const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCBD5E1)),
      onTap: onTap,
    );
  }
}
