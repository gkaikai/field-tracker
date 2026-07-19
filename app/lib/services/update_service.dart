/// APP版本更新检测服务
///
/// 通过 GitHub Releases API 检查最新版本，支持后台下载和静默安装。
///
/// 使用流程:
///   1. APP启动时调用 UpdateService.checkForUpdate()
///   2. 如果有新版本，弹出更新对话框
///   3. 用户点击"立即更新" → 下载APK → 自动跳转安装
///
/// 需要权限:
///   - Android: android.permission.INTERNET
///   - Android: android.permission.REQUEST_INSTALL_PACKAGES (Android 8+)
///   - Android: android.permission.WRITE_EXTERNAL_STORAGE (Android < 10)

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

/// 更新信息模型
class UpdateInfo {
  /// 最新版本号 (如 "1.0.1")
  final String version;

  /// GitHub下载地址
  final String downloadUrl;

  /// 国内加速下载地址（如 gofile.io）
  final String? fastDownloadUrl;

  /// 更新日志
  final String changelog;

  /// 是否强制更新
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.fastDownloadUrl,
    this.changelog = '',
    this.forceUpdate = false,
  });

  /// 当前版本是否低于最新版本
  bool get hasNewVersion => false; // 由 isNewerThan 计算

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      changelog: json['changelog'] as String? ?? '',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
    );
  }
}

/// 版本更新服务
class UpdateService {
  static const String _githubOwner = 'gkaikai';
  static const String _githubRepo = 'field-tracker';
  static const String _apiUrl =
      'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest';

  static bool _isDownloading = false;

  /// 获取当前APP版本号（每次重新获取，安装新版后立即生效）
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 版本号比较 (语义化版本比较)
  /// 返回 true 如果 latest > current
  static bool isNewerThan(String latest, String current) {
    try {
      final latestParts = latest.replaceAll('v', '').split('.');
      final currentParts = current.replaceAll('v', '').split('.');

      final maxLen = latestParts.length > currentParts.length
          ? latestParts.length
          : currentParts.length;

      for (int i = 0; i < maxLen; i++) {
        final l = int.tryParse(i < latestParts.length ? latestParts[i] : '0') ?? 0;
        final c = int.tryParse(i < currentParts.length ? currentParts[i] : '0') ?? 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 从 GitHub Releases API 检查最新版本
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'FieldTracker-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[Update] API请求失败: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // 获取版本号 (tag_name 如 "v1.0.1")
      final tagName = data['tag_name'] as String? ?? '';

      // 获取更新日志 (body)
      final body = data['body'] as String? ?? '';

      // 尝试从body中提取加速下载链接（如 `快速下载: https://gofile.io/d/xxx`）
      String? fastDownloadUrl;
      final urlMatch = RegExp(r'快速下载:\s*(https?://\S+)').firstMatch(body);
      if (urlMatch != null) {
        fastDownloadUrl = urlMatch.group(1);
      }

      // 获取第一个APK附件的下载地址
      String downloadUrl = '';
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }

      if (tagName.isEmpty || downloadUrl.isEmpty) {
        debugPrint('[Update] 未找到版本信息或APK下载链接');
        return null;
      }

      // 检查版本号
      final currentVersion = await getCurrentVersion();
      final hasNew = isNewerThan(tagName, currentVersion);

      if (!hasNew) {
        debugPrint('[Update] 当前已是最新版本 ($currentVersion)');
        return null;
      }

      return UpdateInfo(
        version: tagName,
        downloadUrl: downloadUrl,
        fastDownloadUrl: fastDownloadUrl,
        changelog: body,
        forceUpdate: false,
      );
    } catch (e) {
      debugPrint('[Update] 检查更新失败: $e');
      return null;
    }
  }

  /// 显示更新对话框
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateInfo info,
  ) async {
    if (!context.mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !info.forceUpdate,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.system_update, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text('发现新版本 ${info.version}'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '更新内容:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  info.changelog.isNotEmpty
                      ? info.changelog
                      : '性能优化和Bug修复',
                ),
                if (info.forceUpdate) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ 此版本为强制更新，请及时升级',
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!info.forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('稍后再说'),
              ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('立即更新'),
            ),
          ],
        ),
      ),
    );

    if (result == true && context.mounted) {
      await _startDownload(context, info);
    }
  }

  /// 下载APK并安装（含进度条）
  static Future<void> _startDownload(
    BuildContext context,
    UpdateInfo info,
  ) async {
    if (_isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在下载中，请稍候...')),
      );
      return;
    }

    _isDownloading = true;
    double progress = 0;
    int downloadedBytes = 0;
    int totalBytes = 0;
    final progressNotifier = ValueNotifier<double>(0);

    try {
      // 申请安装权限 (Android 8+)
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          await Permission.requestInstallPackages.request();
        }
      }

      // 显示进度对话框（可更新）
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('正在下载更新...',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(info.version,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (ctx, p, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: p > 0 ? p : null),
                        const SizedBox(height: 8),
                        Text(
                          p > 0
                              ? '${(p * 100).toStringAsFixed(0)}% (${(downloadedBytes / 1048576).toStringAsFixed(1)}MB)'
                              : downloadedBytes > 0
                                  ? '已下载 ${(downloadedBytes / 1048576).toStringAsFixed(1)}MB...'
                                  : '准备中...',
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      );

      // 下载APK - 优先用国内加速，失败则用GitHub直链
      final urls = <String>[];
      if (info.fastDownloadUrl != null) {
        // 将 gofile.io 的下载页面URL转为直接下载链接
        // https://gofile.io/d/xxx → https://pub-xxxxx.gofile.io/download/xxx
        final pageUrl = info.fastDownloadUrl!;
        final match = RegExp(r'gofile\.io/d/([a-zA-Z0-9]+)').firstMatch(pageUrl);
        if (match != null) {
          final code = match.group(1)!;
          urls.add(
              'https://pub-362f39fef5af44aabb2cf15a7b6bd55b.r2.dev/$code');
          urls.add('https://gofile.io/download/$code');
        } else {
          urls.add(pageUrl);
        }
      }
      urls.add(info.downloadUrl);

      http.Response? response;
      for (int i = 0; i < urls.length; i++) {
        try {
          // 带进度追踪的下载
          final client = http.Client();
          final request = http.Request('GET', Uri.parse(urls[i]));
          final streamedResp = await client.send(request)
              .timeout(const Duration(minutes: 5));

          totalBytes = streamedResp.contentLength ?? 0;
          final bytes = <int>[];
          await for (final chunk in streamedResp.stream) {
            bytes.addAll(chunk);
            downloadedBytes += chunk.length;
            if (totalBytes > 0) {
              progress = downloadedBytes / totalBytes;
              progressNotifier.value = progress;
            }
          }
          response = http.Response.bytes(bytes, streamedResp.statusCode,
              headers: streamedResp.headers);
          client.close();

          if (response.statusCode == 200) break;
        } catch (_) {
          if (i < urls.length - 1) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('下载较慢，切换到备用源...'),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            if (!context.mounted) return;
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('下载失败，请稍后重试'),
                backgroundColor: Colors.red,
              ),
            );
            _isDownloading = false;
            return;
          }
        }
      }

      if (response == null || response.statusCode != 200) {
        throw Exception('下载失败: HTTP ${response?.statusCode ?? "无响应"}');
      }

      // 保存到临时目录
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/field-tracker-${info.version}.apk');
      await file.writeAsBytes(response.bodyBytes);

      // 关闭进度对话框
      if (context.mounted) {
        Navigator.of(context).pop(); // 关闭进度对话框
      }

      // 跳转安装
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('安装失败: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // 关闭进度对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
      debugPrint('[Update] 下载安装失败: $e');
    } finally {
      _isDownloading = false;
    }
  }
}
