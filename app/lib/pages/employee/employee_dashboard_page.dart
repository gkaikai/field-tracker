/// 管理员员工模式页面 — 管理员可查看自己的员工数据
library;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/home_card.dart';
import '../map_page.dart';
import '../attendance_page.dart';
import '../track_replay_page.dart';
import '../watermark_camera_page.dart';
import '../report_page.dart';
import '../approval_page.dart';

class EmployeeDashboardPage extends StatelessWidget {
  const EmployeeDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的工作台'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.green[100],
                      child: Text(
                        ((auth.userName ?? '?').isNotEmpty ? auth.userName![0] : '?'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${auth.userName ?? ""}（管理员视角）',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        Text('查看自己的数据', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  HomeCard(icon: Icons.map, title: '实时定位', subtitle: '自己位置', color: Colors.blue,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()))),
                  HomeCard(icon: Icons.fingerprint, title: '打卡记录', subtitle: '我的签到', color: Colors.green,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendancePage()))),
                  HomeCard(icon: Icons.route, title: '我的轨迹', subtitle: '运动路线', color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackReplayPage()))),
                  HomeCard(icon: Icons.camera_alt, title: '水印相机', subtitle: '拍照带水印', color: Colors.purple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatermarkCameraPage()))),
                  HomeCard(icon: Icons.assignment, title: '工作汇报', subtitle: '日报周报', color: Colors.teal,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPage()))),
                  HomeCard(icon: Icons.approval, title: '审批', subtitle: '请假出差', color: Colors.red,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalPage()))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
