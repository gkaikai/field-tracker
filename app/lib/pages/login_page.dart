import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_uploader.dart';
import '../services/error_codes.dart';
import '../config/app_config.dart';

/// 登录页面
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: '13800138000');
  final _passwordController = TextEditingController(text: 'test123456');
  final _authService = AuthService();
  bool _loading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await _authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on ApiException catch (e) {
      // 业务错误码由 ApiService 拦截器统一弹出 Toast，此处仅兜底日志
      debugPrint('Login business error [${e.code}]: ${e.friendlyMessage}');
      Fluttertoast.showToast(
        msg: '登录失败: ${e.code} ${e.friendlyMessage}',
        backgroundColor: Colors.red,
        gravity: ToastGravity.TOP,
      );
    } catch (e, stack) {
      // 极端兜底：拦截器未捕获到的异常
      Fluttertoast.showToast(
        msg: '登录失败: ${e.toString().length > 80 ? e.toString().substring(0, 80) : e.toString()}',
        backgroundColor: Colors.red,
      );
      debugPrint('Login unexpected error: $e\n$stack');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }  // end of _login

  /// 弹出服务器地址设置对话框
  void _showServerSettings() {
    final urlCtrl = TextEditingController(text: AppConfig.baseUrl);
    String? statusText;
    bool saving = false;
    showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('服务器设置'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('当无法连接服务器时，可在此修改服务器地址', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://xxx.serveousercontent.com',
                border: OutlineInputBorder(),
              ),
            ),
            if (statusText != null) ...[
              const SizedBox(height: 8),
              Text(statusText!, style: TextStyle(
                fontSize: 13,
                color: statusText!.startsWith('✅') ? Colors.green : Colors.red,
              )),
            ],
          ]),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final url = urlCtrl.text.trim();
                if (url.isEmpty) {
                  setS(() => statusText = '❌ 地址不能为空');
                  return;
                }
                setS(() { saving = true; statusText = '⏳ 正在保存...'; });
                try {
                  await AppConfig.setServerUrl(url);
                  // 同步更新ApiService和LocationUploader的Dio实例
                  ApiService().updateBaseUrl(url);
                  LocationUploader().updateBaseUrl(url);
                  setS(() => statusText = '✅ 已保存！请重新登录');
                  // 延迟关闭，让用户看到成功提示
                  await Future.delayed(const Duration(seconds: 1));
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setS(() {
                    saving = false;
                    statusText = '❌ 保存失败: $e';
                  });
                }
              },
              child: Text(saving ? '保存中...' : '保存'),
            ),
          ],
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on, size: 80, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text(
                    '外勤定位',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '实时定位 · 轨迹追踪 · 考勤打卡',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    validator: (v) {
                      if (v == null || v.isEmpty) return '请输入手机号';
                      if (!RegExp(r'^1\d{10}$').hasMatch(v.trim())) return '请输入正确的11位手机号';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ))
                          : const Text('登 录',
                              style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                    child: const Text('忘记密码？', style: TextStyle(color: Colors.grey)),
                  ),
                  TextButton(
                    onPressed: _showServerSettings,
                    child: const Text('服务器设置', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
