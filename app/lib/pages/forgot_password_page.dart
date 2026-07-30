// 忘记密码页 v2
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  final _api = ApiService();
  int _step = 0; bool _sending = false; bool _resetting = false;

  @override
  void dispose() {
    _phoneCtrl.dispose(); _codeCtrl.dispose(); _pwdCtrl.dispose();
    _confirmCtrl.dispose(); _captchaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('忘记密码')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 20),
          Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), shape: BoxShape.circle),
            child: const Icon(Icons.lock_outline, size: 28, color: Color(0xFF2563EB))),
          const SizedBox(height: 16),
          Text(['输入手机号', '验证身份', '设置新密码'][_step],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          _buildStepContent(),
        ]),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _step1();
      case 1: return _step2();
      case 2: return _step3();
      default: return const SizedBox();
    }
  }

  Widget _step1() => Column(children: [
    TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: '手机号', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone_android)), keyboardType: TextInputType.phone, maxLength: 11),
    const SizedBox(height: 20),
    TextField(controller: _captchaCtrl, decoration: const InputDecoration(labelText: '图形验证码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.shield)),
      maxLength: 4, keyboardType: TextInputType.number),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
      onPressed: _sending ? null : () { setState(() => _step = 1); },
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
      child: const Text('下一步', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    )),
  ]);

  Widget _step2() => Column(children: [
    Text('验证码已发送至 ${_phoneCtrl.text}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
    const SizedBox(height: 20),
    Row(children: [
      Expanded(child: TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: '验证码', border: OutlineInputBorder()), keyboardType: TextInputType.number, maxLength: 6)),
      const SizedBox(width: 12),
      SizedBox(height: 48, child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEFF6FF), foregroundColor: const Color(0xFF2563EB)), child: const Text('获取验证码'))),
    ]),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
      onPressed: () => setState(() => _step = 2),
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
      child: const Text('下一步', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    )),
  ]);

  Widget _step3() => Column(children: [
    TextField(controller: _pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
    const SizedBox(height: 16),
    TextField(controller: _confirmCtrl, obscureText: true, decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
      onPressed: _resetting ? null : () {},
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
      child: const Text('重置密码', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    )),
  ]);
}
