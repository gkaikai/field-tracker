import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// 忘记密码页面（3步：手机号→验证码→新密码）
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  int _step = 1;
  bool _loading = false;

  // Step 1
  final _phoneCtrl = TextEditingController();
  String? _phoneError;
  // Step 1 - 拼图验证码
  String? _captchaToken;
  String? _captchaSvg;
  final _captchaCtrl = TextEditingController();

  // Step 2
  final _codeCtrl = TextEditingController();
  String? _codeSentTo;

  // Step 3
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  /// 校验手机号是否为11位
  bool _validatePhone(String phone) {
    return RegExp(r'^1\d{10}$').hasMatch(phone);
  }

  /// 获取图形验证码
  Future<void> _loadCaptcha() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final resp = await dio.get('/api/v1/auth/captcha');
      if (mounted) {
        setState(() {
          _captchaToken = resp.data['token'];
          _captchaSvg = resp.data['svg'];
        });
      }
    } catch (_) {}
  }

  /// Step 1: 先验证图形验证码，再发送短信验证码
  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();

    if (!_validatePhone(phone)) {
      setState(() => _phoneError = '请输入11位手机号');
      return;
    }

    // 如果没有验证码，先加载
    if (_captchaToken == null) {
      await _loadCaptcha();
      if (!mounted) return;
    }

    setState(() {
      _phoneError = null;
      _loading = true;
    });

    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));

      // 先校验图形验证码
      if (_captchaToken != null && _captchaCtrl.text.trim().isNotEmpty) {
        try {
          await dio.post('/api/v1/auth/verify-captcha', data: {
            'token': _captchaToken,
            'code': _captchaCtrl.text.trim(),
          });
        } on DioException catch (e) {
          final msg = e.response?.data?['message'] ?? '验证码错误';
          Fluttertoast.showToast(msg: '❌ 图形验证码错误: $msg', backgroundColor: Colors.red);
          _loadCaptcha(); // 刷新验证码
          setState(() => _loading = false);
          return;
        }
      } else {
        Fluttertoast.showToast(msg: '请先输入图形验证码', backgroundColor: Colors.orange);
        setState(() => _loading = false);
        return;
      }

      // 图形验证码通过后，发送短信
      await dio.post('/api/v1/auth/send-code', data: {'phone': phone});

      if (!mounted) return;
      setState(() {
        _codeSentTo = phone;
        _step = 2;
      });
      Fluttertoast.showToast(msg: '✅ 验证码已发送（开发模式请查看服务端日志）', backgroundColor: Colors.green);
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? '发送失败';
      Fluttertoast.showToast(msg: '❌ $msg', backgroundColor: Colors.red);
      if (e.response?.statusCode == 429) {
        // 频率限制，无需刷新
      } else {
        _loadCaptcha(); // 其他错误刷新验证码
        _captchaCtrl.clear();
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '❌ 发送失败: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Step 2: 校验短信验证码
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      Fluttertoast.showToast(msg: '请输入6位验证码', backgroundColor: Colors.orange);
      return;
    }

    setState(() => _loading = true);

    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      await dio.post('/api/v1/auth/verify-code', data: {
        'phone': _codeSentTo,
        'code': code,
      });

      if (!mounted) return;
      setState(() => _step = 3);
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? '验证失败';
      Fluttertoast.showToast(msg: '❌ $msg', backgroundColor: Colors.red);
    } catch (e) {
      Fluttertoast.showToast(msg: '❌ $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Step 3: 重置密码
  Future<void> _resetPassword() async {
    final newPwd = _newPwdCtrl.text;
    final confirm = _confirmPwdCtrl.text;

    if (newPwd.length < 6) {
      Fluttertoast.showToast(msg: '密码至少6位', backgroundColor: Colors.orange);
      return;
    }
    if (newPwd != confirm) {
      Fluttertoast.showToast(msg: '两次密码不一致', backgroundColor: Colors.orange);
      return;
    }

    setState(() => _loading = true);

    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      await dio.post('/api/v1/auth/forgot-password', data: {
        'phone': _codeSentTo,
        'newPassword': newPwd,
      });

      if (!mounted) return;
      Fluttertoast.showToast(msg: '✅ 密码重置成功，请使用新密码登录', backgroundColor: Colors.green);
      Navigator.pop(context);
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? '重置失败';
      Fluttertoast.showToast(msg: '❌ $msg', backgroundColor: Colors.red);
    } catch (e) {
      Fluttertoast.showToast(msg: '❌ $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('忘记密码'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 步骤指示器
            Row(
              children: [
                _stepIndicator(1, '验证手机', _step >= 1),
                Expanded(child: Divider(color: _step >= 2 ? Colors.blue : Colors.grey[300])),
                _stepIndicator(2, '短信验证', _step >= 2),
                Expanded(child: Divider(color: _step >= 3 ? Colors.blue : Colors.grey[300])),
                _stepIndicator(3, '设置密码', _step >= 3),
              ],
            ),
            const SizedBox(height: 40),
            if (_step == 1) _buildStep1(),
            if (_step == 2) _buildStep2(),
            if (_step == 3) _buildStep3(),
          ],
        ),
      ),
    );
  }

  Widget _stepIndicator(int num, String label, bool active) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.blue : Colors.grey[300],
          ),
          child: Center(
            child: active
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text('$num', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: active ? Colors.blue : Colors.grey)),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('请输入注册时使用的手机号', style: TextStyle(fontSize: 16, color: Colors.black87)),
        const SizedBox(height: 20),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          decoration: InputDecoration(
            labelText: '手机号',
            prefixIcon: const Icon(Icons.phone_android),
            border: const OutlineInputBorder(),
            errorText: _phoneError,
            counterText: '',
          ),
          onChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        ),
        const SizedBox(height: 16),
        // 图形验证码区域
        if (_captchaSvg != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SvgPicture.string(
                        _captchaSvg!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () { _loadCaptcha(); _captchaCtrl.clear(); },
                  tooltip: '换一张',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _captchaCtrl,
            decoration: const InputDecoration(
              labelText: '计算结果',
              hintText: '输入计算结果',
              prefixIcon: Icon(Icons.calculate_outlined, size: 20),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
        ] else
          TextButton(
            onPressed: _loadCaptcha,
            child: const Text('点击加载验证码'),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendCode,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('获取验证码', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('验证码已发送至 $_codeSentTo', style: const TextStyle(fontSize: 16, color: Colors.black87)),
        const SizedBox(height: 20),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '短信验证码',
            prefixIcon: Icon(Icons.sms),
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _loading ? null : _verifyCode,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('验证', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('设置新密码', style: TextStyle(fontSize: 16, color: Colors.black87)),
        const SizedBox(height: 20),
        TextField(
          controller: _newPwdCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '新密码（至少6位）',
            prefixIcon: Icon(Icons.lock),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPwdCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '确认新密码',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _loading ? null : _resetPassword,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('重置密码', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
