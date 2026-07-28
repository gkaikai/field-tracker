import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key});
  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  final _auth = AuthService();
  List _photos = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final r = await dio.get('/api/v1/upload/photos',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      setState(() { _photos = r.data['photos'] ?? []; _loading = false; });
    } catch (e) { debugPrint('加载照片列表失败: $e'); if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e'))); } }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('照片列表'), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty ? const Center(child: Text('暂无照片'))
          : RefreshIndicator(onRefresh: _load, child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
              itemCount: _photos.length,
              itemBuilder: (_, i) {
                final p = _photos[i];
                final url = '${AppConfig.baseUrl}${p['url'] ?? ''}';
                return GestureDetector(
                  onTap: () => showDialog(context: context, builder: (_) => Dialog(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Image.network(url, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64, color: Colors.grey)),
                      Padding(padding: const EdgeInsets.all(8), child: Text(p['time']?.toString() ?? '')),
                    ]))),
                  child: Image.network(url, fit: BoxFit.cover),
                );
              },
            )),
    );
  }
}
