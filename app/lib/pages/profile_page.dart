import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/offline_service.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth = AuthService();
  final _oldPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool _loading = false;
  String? _msg;

  Future<void> _changePassword() async {
    if (_oldPwdCtrl.text.isEmpty || _newPwdCtrl.text.isEmpty) {
      setState(() => _msg = '请填写完整');
      return;
    }
    if (_newPwdCtrl.text != _confirmPwdCtrl.text) {
      setState(() => _msg = '两次密码不一致');
      return;
    }
    if (_newPwdCtrl.text.length < 6) {
      setState(() => _msg = '密码至少6位');
      return;
    }
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      await dio.post('/api/v1/auth/change-password', data: {
        'oldPassword': _oldPwdCtrl.text,
        'newPassword': _newPwdCtrl.text,
      }, options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      setState(() { _msg = '✅ 修改成功'; _oldPwdCtrl.clear(); _newPwdCtrl.clear(); _confirmPwdCtrl.clear(); });
    } catch (e) {
      setState(() => _msg = '❌ 修改失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _oldPwdCtrl.dispose(); _newPwdCtrl.dispose(); _confirmPwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('个人设置'), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(radius: 30, backgroundColor: Colors.blue[100],
                  child: Text((_auth.userName ?? '?')[0], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue))),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_auth.userName ?? '未设置', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
              ]),
            )),
            const SizedBox(height: 20),
            const Text('数据同步', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('同步离线数据', style: TextStyle(fontSize: 16)),
                onPressed: () async {
                  final svc = OfflineService();
                  final count = await svc.offlineCount();
                  if (!context.mounted) return;
                  if (count == 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无离线数据需要同步'))); return; }
                  final synced = await svc.syncAll();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步完成: $synced 条')));
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text('修改密码', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: _oldPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '当前密码', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _newPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _confirmPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            if (_msg != null) Text(_msg!, style: TextStyle(color: _msg!.contains('✅') ? Colors.green : Colors.red)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(onPressed: _loading ? null : _changePassword,
                child: _loading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('修改密码', style: TextStyle(fontSize: 16)))),
          ],
        ),
      ),
    );
  }
}
