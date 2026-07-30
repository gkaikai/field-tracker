// 登录页 v2 — 品牌化设计
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_uploader.dart';
import '../config/app_config.dart';
import '../services/error_codes.dart';
import '../theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;

  @override
  void dispose() { _usernameController.dispose(); _passwordController.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await _authService.login(_usernameController.text.trim(), _passwordController.text);
      LocationUploader().setUserId(_authService.userId ?? '');
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on ApiException catch (e) {
      Fluttertoast.showToast(msg: '登录失败: ${e.friendlyMessage}', backgroundColor: Colors.red, gravity: ToastGravity.TOP);
    } catch (e, stack) {
      Fluttertoast.showToast(msg: '登录失败', backgroundColor: Colors.red);
    } finally { if (mounted) setState(() => _loading = false); }
  }

  void _showServerSettings() {
    final urlCtrl = TextEditingController(text: AppConfig.baseUrl);
    String? statusText; bool saving = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('服务器设置'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('当无法连接服务器时，可在此修改服务器地址', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: '服务器地址', hintText: 'https://...', border: OutlineInputBorder())),
        if (statusText != null) ...[const SizedBox(height: 8), Text(statusText!, style: TextStyle(fontSize: 13, color: statusText!.startsWith('✅') ? Colors.green : Colors.red))],
      ]),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: saving ? null : () async {
          final url = urlCtrl.text.trim();
          if (url.isEmpty) { setS(() => statusText = '❌ 地址不能为空'); return; }
          setS(() { saving = true; statusText = '⏳ 正在保存...'; });
          try {
            await AppConfig.setServerUrl(url);
            ApiService().updateBaseUrl(url); LocationUploader().updateBaseUrl(url);
            setS(() => statusText = '✅ 已保存！请重新登录');
            await Future.delayed(const Duration(seconds: 1));
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) { setS(() { saving = false; statusText = '❌ 保存失败'; }); }
        }, child: Text(saving ? '保存中...' : '保存')),
      ],
    ))).then((_) => urlCtrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 品牌头部
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 60, bottom: 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.8)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: Column(children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.location_on, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text('外勤定位', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('实时定位 · 轨迹追踪 · 考勤打卡', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
                ]),
              ),
              // 登录表单
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Form(
                  key: _formKey,
                  child: Column(children: [
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: '手机号', prefixIcon: Icon(Icons.phone_android), border: OutlineInputBorder()),
                      keyboardType: TextInputType.phone, maxLength: 11,
                      validator: (v) {
                        if (v == null || v.isEmpty) return '请输入手机号';
                        if (!RegExp(r'^1\d{10}$').hasMatch(v.trim())) return '请输入正确的11位手机号';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController, obscureText: true,
                      decoration: const InputDecoration(labelText: '密码', prefixIcon: Icon(Icons.lock), border: OutlineInputBorder()),
                      validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('登 录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                        child: const Text('忘记密码？', style: TextStyle(color: Colors.grey))),
                    TextButton(onPressed: _showServerSettings,
                        child: const Text('服务器设置', style: TextStyle(color: Colors.grey, fontSize: 12))),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
