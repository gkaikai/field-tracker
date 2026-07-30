// WiFi打卡页 v2
import 'package:flutter/material.dart';

class WifiCheckinPage extends StatefulWidget {
  const WifiCheckinPage({super.key});
  @override
  State<WifiCheckinPage> createState() => _WifiCheckinPageState();
}

class _WifiCheckinPageState extends State<WifiCheckinPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi打卡')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi, size: 72, color: Color(0xFF2563EB)),
            const SizedBox(height: 16),
            const Text('WiFi 打卡', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('连接指定 WiFi 后自动签到', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBBF7D0)), color: const Color(0xFFF0FDF4)),
              child: Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.wifi, color: Color(0xFF16A34A), size: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Office-WiFi-5G', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('信号强度: ████ 强', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                  child: const Text('已连接', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text('已连接指定 WiFi，可自动打卡', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.wifi),
                label: const Text('WiFi 签到', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
