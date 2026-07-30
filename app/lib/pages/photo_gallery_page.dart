// 照片列表页 v2 — 网格+渐变色占位+点击放大
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key});
  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  final _api = ApiService();
  List _photos = []; bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/api/v1/upload/photos');
      setState(() { _photos = r.data['photos'] ?? []; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('照片列表'), actions: [
        if (_photos.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 12), child: Text('共 ${_photos.length} 张', style: const TextStyle(fontSize: 13))),
      ]),
      body: _loading
          ? _buildSkeleton()
          : _photos.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF5F3FF), shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, size: 28, color: Color(0xFF7C3AED))),
                  const SizedBox(height: 12), const Text('暂无照片', style: TextStyle(fontSize: 15, color: Colors.grey)),
                ]))
              : RefreshIndicator(onRefresh: _load, child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                  itemCount: _photos.length,
                  itemBuilder: (_, i) {
                    final p = _photos[i];
                    final url = '${AppConfig.baseUrl}${p['url'] ?? ''}';
                    final colors = [const Color(0xFF60A5FA), const Color(0xFF34D399), const Color(0xFFFBBF24), const Color(0xFFA78BFA), const Color(0xFFF87171), const Color(0xFF38BDF8)];
                    return GestureDetector(
                      onTap: () => showDialog(context: context, builder: (_) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(height: 200, color: Colors.grey.shade900, child: const Icon(Icons.broken_image, size: 48, color: Colors.grey)))),
                          const SizedBox(height: 8),
                          Text(p['time']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      )),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(url, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: BoxDecoration(gradient: LinearGradient(colors: [colors[i % colors.length], colors[(i + 1) % colors.length]])),
                            child: const Center(child: Icon(Icons.image, color: Colors.white24, size: 28)),
                          ),
                        ),
                      ),
                    );
                  },
                )),
    );
  }

  Widget _buildSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
      itemCount: 9,
      itemBuilder: (_, i) => Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
