// 水印相机 v2 — 底部操作栏分步
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import 'package:field_tracker/services/amap_location_service.dart';

class WatermarkCameraPage extends StatefulWidget {
  final void Function(String photoUrl)? onPhotoTaken;
  const WatermarkCameraPage({super.key, this.onPhotoTaken});
  @override
  State<WatermarkCameraPage> createState() => _WatermarkCameraPageState();
}

class _WatermarkCameraPageState extends State<WatermarkCameraPage> {
  CameraController? _controller; List<CameraDescription>? _cameras;
  bool _isReady = false, _isProcessing = false, _isUploading = false;
  String? _lastPhotoPath, _lastPhotoUploadUrl;
  double? _currentLat, _currentLng;
  String _address = '';
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _initCamera(); _getLocation();
  }

  @override
  void dispose() { _controller?.dispose(); super.dispose(); }

  Future<void> _getLocation() async {
    final loc = AmapLocationService();
    if (!loc.isRunning) await loc.startTracking();
    if (loc.currentLat != null && loc.currentLng != null) {
      if (mounted) setState(() { _currentLat = loc.currentLat; _currentLng = loc.currentLng; _address = '${loc.currentLat!.toStringAsFixed(4)}, ${loc.currentLng!.toStringAsFixed(4)}'; });
    }
  }

  Future<void> _initCamera() async {
    try { _cameras = await availableCameras(); if (_cameras == null || _cameras!.isEmpty) return;
      _controller = CameraController(_cameras![0], ResolutionPreset.high);
      await _controller!.initialize(); if (mounted) setState(() => _isReady = true);
    } catch (e) { debugPrint('相机初始化失败: $e'); }
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isProcessing = true);
    try {
      final xFile = await _controller!.takePicture();
      final path = await _addWatermark(xFile.path);
      if (path != null) setState(() { _lastPhotoPath = path; _isProcessing = false; });
    } catch (e) { setState(() => _isProcessing = false); }
  }

  Future<String?> _addWatermark(String imagePath) async {
    try {
      final original = img.decodeImage(await File(imagePath).readAsBytes());
      if (original == null) return null;
      final w = original.width; final h = original.height;
      final fontSize = (h * 0.035).round().clamp(14, 36);
      final font = fontSize > 20 ? img.arial24 : img.arial14;
      final barHeight = (h * 0.08).round().clamp(30, 80);
      final drawable = img.copyResize(original, width: w);
      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final addrStr = _address.isNotEmpty ? _address : '${_currentLat?.toStringAsFixed(4) ?? ""}, ${_currentLng?.toStringAsFixed(4) ?? ""}';
      final userName = _auth.userName ?? '';

      // 底部半透明黑条
      for (int py = h - barHeight; py < h && py < drawable.height; py++) {
        for (int px = 0; px < w && px < drawable.width; px++) {
          drawable.setPixelRgba(px, py, 0, 0, 0, 160);
        }
      }
      // 写文字
      img.drawString(drawable, '外勤定位', font: font, x: fontSize ~/ 2, y: h - barHeight + 8, color: img.ColorRgba8(255, 255, 255, 255));
      img.drawString(drawable, '$dateStr  $addrStr', font: font, x: fontSize ~/ 2, y: h - barHeight + 8 + fontSize + 2, color: img.ColorRgba8(255, 255, 255, 255));
      img.drawString(drawable, userName, font: font, x: fontSize ~/ 2, y: h - barHeight + 8 + (fontSize + 2) * 2, color: img.ColorRgba8(255, 255, 255, 255));

      final pngBytes = img.encodePng(drawable);
      final outDir = await getTemporaryDirectory();
      final outPath = '${outDir.path}/wm_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(pngBytes);
      return outPath;
    } catch (e) {
      debugPrint('Watermark error: $e');
      return null;
    }
  }

  Future<void> _uploadPhoto() async {
    if (_lastPhotoPath == null) return;
    setState(() => _isUploading = true);
    try {
      final file = File(_lastPhotoPath!);
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path, filename: 'wm_${DateTime.now().millisecondsSinceEpoch}.png'),
        'lat': _currentLat ?? 0, 'lng': _currentLng ?? 0, 'address': _address,
      });
      final resp = await ApiService().uploadFile('/api/v1/upload/photo', formData);
      final url = resp.data['url'] as String?;
      if (mounted && url != null) {
        setState(() => _lastPhotoUploadUrl = url);
        widget.onPhotoTaken?.call(url);
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    } finally { if (mounted) setState(() => _isUploading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('水印拍照'), actions: [
        if (_lastPhotoPath != null && _lastPhotoUploadUrl == null)
          TextButton.icon(onPressed: _uploadPhoto, icon: _isUploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload, color: Colors.white), label: const Text('上传', style: TextStyle(color: Colors.white))),
      ]),
      body: Column(children: [
        // Camera preview / photo preview
        Expanded(
          child: _lastPhotoPath != null
              ? Stack(children: [
                  Image.file(File(_lastPhotoPath!), fit: BoxFit.contain, width: double.infinity, height: double.infinity),
                  Positioned(bottom: 8, left: 8, right: 8,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          GestureDetector(onTap: () => setState(() { _lastPhotoPath = null; _lastPhotoUploadUrl = null; }), child: const Icon(Icons.refresh, color: Colors.white, size: 18)),
                          const SizedBox(width: 16),
                          GestureDetector(onTap: _uploadPhoto, child: const Icon(Icons.check_circle, color: Colors.green, size: 22)),
                        ]),
                      ),
                    ]),
                  ),
                ])
              : _controller != null && _controller!.value.isInitialized
                  ? CameraPreview(_controller!)
                  : const Center(child: Text('相机初始化中...', style: TextStyle(color: Colors.grey))),
        ),
        // Bottom action bar
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _actionBtn(Icons.camera_alt, '拍照', _isReady && !_isProcessing ? _takePhoto : null),
            const SizedBox(width: 40),
            _actionBtn(Icons.flip_camera_android, '翻转', () async {
              if (_cameras == null || _cameras!.length < 2) return;
              final idx = _cameras!.indexWhere((c) => c.lensDirection != _controller!.description.lensDirection);
              if (idx < 0) return;
              await _controller?.dispose();
              _controller = CameraController(_cameras![idx], ResolutionPreset.high);
              await _controller!.initialize();
              if (mounted) setState(() {});
            }),
          ]),
        ),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: onTap != null ? Colors.white : Colors.grey.shade700),
          child: Icon(icon, color: onTap != null ? Colors.black87 : Colors.grey, size: 22)),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 11, color: onTap != null ? Colors.white70 : Colors.grey)),
      ]),
    );
  }
}
