// 拍照水印页面

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class WatermarkCameraPage extends StatefulWidget {
  final void Function(String photoUrl)? onPhotoTaken;

  const WatermarkCameraPage({super.key, this.onPhotoTaken});

  @override
  State<WatermarkCameraPage> createState() => _WatermarkCameraPageState();
}

class _WatermarkCameraPageState extends State<WatermarkCameraPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isReady = false;
  bool _isProcessing = false;
  bool _isUploading = false;
  String? _lastPhotoPath;
  String? _lastPhotoUploadUrl;

  Position? _position;
  String _address = '';
  String _currentTime = '';
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _currentTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    _initCamera();
    _getLocation();
  }

  Future<void> _getLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _position = pos;
          _address =
              '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      _controller = CameraController(camera, ResolutionPreset.high);
      await _controller!.initialize();
      if (mounted) setState(() => _isReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final xFile = await _controller!.takePicture();
      final now = DateTime.now();
      _currentTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

      final watermarkedPath = await _addWatermark(xFile.path);
      if (mounted) {
        setState(() {
          _lastPhotoPath = watermarkedPath ?? xFile.path;
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('Take photo error: $e');
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<String?> _addWatermark(String imagePath) async {
    try {
      final original = img.decodeImage(await File(imagePath).readAsBytes());
      if (original == null) return null;

      final drawable = img.Image.from(original);
      final w = drawable.width;
      final h = drawable.height;

      final userName = _auth.userName ?? '用户';
      final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final latStr = _position?.latitude.toStringAsFixed(4) ?? '---';
      final lngStr = _position?.longitude.toStringAsFixed(4) ?? '---';
      final addrStr = _address;

      final fontSize = (w / 30).round().clamp(16, 48);
      final barHeight = (h * 0.12).round();

      // 底部半透明黑条
      _fillRect(drawable, 0, h - barHeight, w, barHeight,
          img.ColorRgba8(0, 0, 0, 160));

      // 顶部半透明黑条
      final topBarHeight = (h * 0.06).round();
      _fillRect(drawable, 0, 0, w, topBarHeight, img.ColorRgba8(0, 0, 0, 140));

      // 写文字
      final font = img.arial24;
      // 顶部：应用名
      img.drawString(drawable, '外勤定位',
          font: font, x: fontSize ~/ 2, y: 4,
          color: img.ColorRgba8(255, 255, 255, 255));

      // 底部：时间
      img.drawString(drawable, dateStr,
          font: font, x: fontSize ~/ 2, y: h - barHeight + 8,
          color: img.ColorRgba8(255, 255, 255, 255));
      // 底部：位置和用户名
      img.drawString(drawable, '$addrStr  |  $userName',
          font: font, x: fontSize ~/ 2, y: h - barHeight + 8 + fontSize + 4,
          color: img.ColorRgba8(255, 255, 255, 255));

      final pngBytes = img.encodePng(drawable);
      final outDir = await getTemporaryDirectory();
      final outPath =
          '${outDir.path}/wm_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(pngBytes);
      return outPath;
    } catch (e) {
      debugPrint('Watermark error: $e');
      return null;
    }
  }

  void _fillRect(
      img.Image image, int x, int y, int w, int h, img.ColorRgba8 color) {
    for (int py = y; py < y + h && py < image.height; py++) {
      for (int px = x; px < x + w && px < image.width; px++) {
        image.setPixelRgba(px, py, color.r, color.g, color.b, color.a);
      }
    }
  }

  Future<void> _uploadPhoto() async {
    if (_lastPhotoPath == null) return;
    setState(() => _isUploading = true);

    try {
      final file = File(_lastPhotoPath!);
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path,
            filename:
                'wm_${DateTime.now().millisecondsSinceEpoch}.png'),
        'lat': _position?.latitude ?? 0,
        'lng': _position?.longitude ?? 0,
        'address': _address,
      });

      final resp =
          await ApiService().uploadFile('/api/v1/upload/photo', formData);
      final data = resp.data as Map<String, dynamic>;
      final url = data['url'] as String?;

      if (mounted && url != null) {
        setState(() => _lastPhotoUploadUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('水印照片上传成功'), backgroundColor: Colors.green),
        );
        widget.onPhotoTaken?.call(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照水印'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_lastPhotoPath != null && _lastPhotoUploadUrl == null)
            TextButton.icon(
              onPressed: _isUploading ? null : _uploadPhoto,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload, color: Colors.white),
              label: Text(_isUploading ? '上传中...' : '上传',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          // 相机/照片预览
          Expanded(
            child:
                _lastPhotoPath != null ? _buildPhotoPreview() : _buildCamera(),
          ),

          // 位置信息
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[900],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📅 $_currentTime',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 4),
                Text('📍 $_address',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),

          // 操作按钮
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_lastPhotoPath != null)
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.cached,
                            color: Colors.white, size: 32),
                        onPressed: () => setState(() {
                          _lastPhotoPath = null;
                          _lastPhotoUploadUrl = null;
                        }),
                      ),
                      const Text('重拍',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  )
                else
                  const SizedBox(width: 60),

                GestureDetector(
                  onTap: _isProcessing || _isUploading
                      ? null
                      : (_lastPhotoPath == null
                          ? _takePhoto
                          : () => _uploadPhoto().then((_) {
                                if (mounted) Navigator.pop(context);
                              })),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          _lastPhotoPath == null ? Colors.white : Colors.green,
                      border:
                          Border.all(color: Colors.white30, width: 4),
                    ),
                    child: Center(
                      child: _isProcessing || _isUploading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Icon(
                              _lastPhotoPath == null
                                  ? Icons.camera_alt
                                  : Icons.check,
                              color: _lastPhotoPath == null
                                  ? Colors.black87
                                  : Colors.white,
                              size: 32,
                            ),
                    ),
                  ),
                ),

                if (_lastPhotoPath == null &&
                    _cameras != null &&
                    _cameras!.length > 1)
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.flip_camera_android,
                            color: Colors.white, size: 32),
                        onPressed: _switchCamera,
                      ),
                      const Text('翻转',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  )
                else
                  const SizedBox(width: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    if (!_isReady) {
      return const Center(child: CircularProgressIndicator());
    }
    return CameraPreview(_controller!);
  }

  Widget _buildPhotoPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(_lastPhotoPath!), fit: BoxFit.contain),
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.all(6),
            color: Colors.black87,
            child: const Text('外勤定位',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black87,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📅 $_currentTime',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                Text('📍 $_address',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _switchCamera() {
    if (_cameras == null || _cameras!.length < 2) return;
    final lens = _controller?.description.lensDirection ==
            CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final desc = _cameras!.firstWhere((c) => c.lensDirection == lens);
    _controller = CameraController(desc, ResolutionPreset.high);
    _controller!.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }
}
