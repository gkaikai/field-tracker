// 独立电子围栏编辑页面 — 全屏地图可视化编辑
// 与创建页面完全分离，不共享任何状态
import 'dart:async';
import 'dart:math' show cos, sin, pi;
import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import '../config/amap_key.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class FenceEditPage extends StatefulWidget {
  final Map<String, dynamic> fence;
  const FenceEditPage({super.key, required this.fence});

  @override
  State<FenceEditPage> createState() => _FenceEditPageState();
}

class _FenceEditPageState extends State<FenceEditPage> {
  final ApiService _api = ApiService();

  // 原始围栏数据（用于取消时恢复）
  final Map<String, dynamic> _original;

  // 名称
  late TextEditingController _nameCtrl;

  // 形状类型
  late bool _isCircle;

  // === 圆形围栏编辑 state（与创建完全隔离）===
  late LatLng? _editCenter;
  late double _editRadius;

  // === 多边形围栏编辑 state（与创建完全隔离）===
  late List<LatLng> _editPoints;
  late bool _editComplete;

  // 地图控制器
  AMapController? _mapController;

  // 保存状态
  bool _saving = false;

  // 地图初始位置
  CameraPosition _initialCameraPos;

  // 地址搜索
  final _searchCtrl = TextEditingController();
  bool _searchLoading = false;
  List<Map<String, String>> _searchSuggestions = [];
  bool _showSuggestions = false;
  Timer? _searchDebounce;

  _FenceEditPageState()
      : _original = {},
        _initialCameraPos = const CameraPosition(
          target: LatLng(22.5431, 114.0579),
          zoom: 14,
        );

  @override
  void initState() {
    super.initState();
    final f = widget.fence;
    _original.clear();
    _original.addAll(f);

    _nameCtrl = TextEditingController(text: f['name']?.toString() ?? '');

    _isCircle = (f['shapeType']?.toString() ?? 'circle') == 'circle';

    if (_isCircle) {
      final lat = (f['centerLat'] as num?)?.toDouble() ?? 22.5431;
      final lng = (f['centerLng'] as num?)?.toDouble() ?? 114.0579;
      _editCenter = LatLng(lat, lng);
      _editRadius = (f['radiusMeters'] as num?)?.toDouble() ?? 300;
      _editPoints = [];
      _editComplete = true;

      _initialCameraPos = CameraPosition(
        target: LatLng(lat, lng),
        zoom: 15,
      );
    } else {
      final rawCoords = f['coordinates'] as List? ?? [];
      _editPoints = rawCoords.map((c) {
        if (c is Map) {
          return LatLng(
            (c['lat'] as num?)?.toDouble() ?? 0,
            (c['lng'] as num?)?.toDouble() ?? 0,
          );
        }
        return LatLng(0, 0);
      }).toList();
      _editComplete = true;
      _editCenter = null;
      _editRadius = 300;

      if (_editPoints.isNotEmpty) {
        _initialCameraPos = CameraPosition(
          target: _editPoints.first,
          zoom: 15,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ========== 地图辅助：圆近似多边形 ==========
  List<LatLng> _circlePolygonPoints(LatLng center, double radiusMeters) {
    const n = 64;
    const latPerM = 1.0 / 111320.0;
    final lngPerM =
        1.0 / (111320.0 * cos(center.latitude * pi / 180.0));
    return List.generate(n, (i) {
      final angle = 2 * pi * i / n;
      return LatLng(
        center.latitude + radiusMeters * cos(angle) * latPerM,
        center.longitude + radiusMeters * sin(angle) * lngPerM,
      );
    });
  }

  // ========== 保存 ==========
  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showToast('请输入围栏名称', Colors.orange);
      return;
    }
    if (_isCircle && _editCenter == null) {
      _showToast('请设置围栏中心点', Colors.orange);
      return;
    }
    if (!_isCircle && _editPoints.length < 3) {
      _showToast('多边形至少需要3个顶点', Colors.orange);
      return;
    }

    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{'name': name};
      if (_isCircle) {
        data['centerLat'] = _editCenter!.latitude;
        data['centerLng'] = _editCenter!.longitude;
        data['radiusMeters'] = _editRadius;
        data['shapeType'] = 'circle';
      } else {
        data['coordinates'] =
            _editPoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
        data['shapeType'] = 'polygon';
      }

      await _api.put('/api/v1/fences/${widget.fence['id']}', data: data);
      if (mounted) {
        _showToast('围栏已更新', Colors.green);
        Navigator.pop(context, true); // return true = changed
      }
    } catch (e) {
      if (mounted) {
        _showToast('更新失败', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showToast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  // ========== 搜索 ==========
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchSuggestions(value.trim());
    });
  }

  Future<void> _fetchSuggestions(String keyword) async {
    try {
      final resp = await ApiService.amapDio.get(
        'https://restapi.amap.com/v3/place/text',
        queryParameters: {
          'key': AMapConfig.webServiceKey,
          'keywords': keyword,
          'output': 'JSON',
          'offset': '15',
          'page': '1',
          'extensions': 'base',
        },
      );
      if (resp.data['status'] != '1') {
        if (mounted) setState(() => _showSuggestions = false);
        return;
      }
      final pois = resp.data['pois'] as List?;
      if (pois == null || pois.isEmpty) {
        if (mounted) setState(() => _showSuggestions = false);
        return;
      }
      if (mounted) {
        setState(() {
          _searchSuggestions = pois.map((t) {
            final m = t as Map<String, dynamic>;
            return {
              'name': (m['name'] ?? '').toString(),
              'address': (m['address'] ?? '').toString(),
              'location': (m['location'] ?? '').toString(),
              'district': (m['district'] ?? '').toString(),
            };
          }).where((x) => x['location'] != null && x['location']!.isNotEmpty).toList();
          _showSuggestions = _searchSuggestions.isNotEmpty;
        });
      }
    } catch (_) {
      debugPrint('获取POI建议失败');
    }
  }

  void _onSuggestionTap(Map<String, String> item) {
    setState(() => _showSuggestions = false);
    final loc = item['location'] ?? '';
    final parts = loc.split(',');
    if (parts.length != 2) return;
    final lat = double.tryParse(parts[1]);
    final lng = double.tryParse(parts[0]);
    if (lat == null || lng == null) return;
    final name = item['name'] ?? '';
    final newPos = LatLng(lat, lng);

    setState(() {
      _searchCtrl.text = name;
      if (_isCircle) {
        _editCenter = newPos;
      } else {
        _editPoints.add(newPos);
      }
    });
    _mapController?.moveCamera(
      CameraUpdate.newLatLngZoom(newPos, 16),
    );
  }

  // ========== 地图手势 ==========
  void _onMapTap(LatLng latlng) {
    if (_isCircle) {
      setState(() {
        _editCenter = latlng;
      });
    } else {
      setState(() {
        _editPoints.add(latlng);
      });
    }
  }

  // ========== 构建 ==========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCircle ? '编辑圆形围栏' : '编辑多边形围栏'),
        backgroundColor: context.adminPrimary,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          _buildSearchBar(),
          // 地图 (Expanded)
          Expanded(
            child: Stack(
              children: [
                _buildMap(),
                // 搜索建议 overlay（在 Column 之外，避免 PlatformView resize 问题）
                if (_showSuggestions && _searchSuggestions.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 0,
                    child: _buildSuggestionsOverlay(),
                  ),
              ],
            ),
          ),
          // 底部控制
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: '搜索地址定位',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                  isDense: true,
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _searchSuggestions = [];
                              _showSuggestions = false;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: _searchLoading
                  ? null
                  : () {
                      final kw = _searchCtrl.text.trim();
                      if (kw.isNotEmpty) _searchAddress(kw);
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _searchLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search, size: 18),
                        SizedBox(width: 4),
                        Text('搜索', style: TextStyle(fontSize: 13)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _searchAddress(String keyword) async {
    if (keyword.isEmpty) return;
    setState(() {
      _searchLoading = true;
      _showSuggestions = false;
    });
    try {
      final resp = await ApiService.amapDio.get(
        'https://restapi.amap.com/v3/place/text',
        queryParameters: {
          'key': AMapConfig.webServiceKey,
          'keywords': keyword,
          'output': 'JSON',
          'offset': '1',
          'page': '1',
          'extensions': 'base',
        },
      );
      if (resp.data['status'] != '1') {
        if (mounted) _showToast('搜索失败: ${resp.data['info'] ?? '未知错误'}', Colors.orange);
        return;
      }
      Map<String, dynamic>? target;
      final pois = resp.data['pois'] as List?;
      if (pois != null && pois.isNotEmpty) {
        final first = pois[0] as Map<String, dynamic>;
        final location = first['location'] as String? ?? '';
        final parts = location.split(',');
        if (parts.length == 2) {
          final lat2 = double.tryParse(parts[1]);
          final lng2 = double.tryParse(parts[0]);
          if (lat2 != null && lng2 != null) {
            target = {
              'lat': lat2,
              'lng': lng2,
              'name': (first['name'] ?? '').toString(),
            };
          }
        }
      }
      if (target == null) {
        // 回退地理编码
        try {
          final geoResp = await ApiService.amapDio.get(
            'https://restapi.amap.com/v3/geocode/geo',
            queryParameters: {
              'key': AMapConfig.webServiceKey,
              'address': keyword,
              'output': 'JSON',
              'city': '',
            },
          );
          if (geoResp.data['status'] == '1') {
            final geocodes = geoResp.data['geocodes'] as List?;
            if (geocodes != null && geocodes.isNotEmpty) {
              final loc = geocodes[0]['location'] as String? ?? '';
              final parts = loc.split(',');
              if (parts.length == 2) {
                final glat = double.tryParse(parts[1]);
                final glng = double.tryParse(parts[0]);
                if (glat != null && glng != null) {
                  target = {'lat': glat, 'lng': glng, 'name': keyword};
                }
              }
            }
          }
        } catch (_) {}
      }
      if (target == null) {
        if (mounted) _showToast('未找到相关地点', Colors.orange);
        return;
      }
      final lat = target['lat'] as double;
      final lng = target['lng'] as double;
      final newPos = LatLng(lat, lng);
      setState(() {
        _searchCtrl.text = target!['name'] as String;
        if (_isCircle) {
          _editCenter = newPos;
        } else {
          _editPoints.add(newPos);
        }
      });
      _mapController?.moveCamera(CameraUpdate.newLatLngZoom(newPos, 16));
    } catch (e) {
      if (mounted) _showToast('搜索失败', Colors.red);
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Widget _buildSuggestionsOverlay() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: _searchSuggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 12, endIndent: 12),
        itemBuilder: (context, i) {
          final item = _searchSuggestions[i];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
            title: Text(item['name'] ?? '', style: const TextStyle(fontSize: 14, color: Colors.black87)),
            subtitle: item['address'] != null && item['address']!.isNotEmpty
                ? Text(item['address']!, style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            onTap: () => _onSuggestionTap(item),
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    final polygons = <Polygon>{};
    if (_isCircle && _editCenter != null) {
      polygons.add(Polygon(
        points: _circlePolygonPoints(_editCenter!, _editRadius),
        strokeWidth: 2,
        strokeColor: Colors.red,
        fillColor: Colors.red.withOpacity(0.15),
      ));
    }

    final polylines = <Polyline>{};
    if (!_isCircle && _editPoints.length >= 2) {
      final pts = List<LatLng>.from(_editPoints);
      if (_editComplete && _editPoints.length >= 3) {
        pts.add(_editPoints.first);
      }
      polylines.add(Polyline(
        points: pts,
        color: Colors.blue,
        width: 3,
      ));
    }
    if (!_isCircle && _editComplete && _editPoints.length >= 3) {
      polygons.add(Polygon(
        points: List<LatLng>.from(_editPoints),
        strokeWidth: 0,
        fillColor: Colors.blue.withOpacity(0.12),
      ));
    }

    final markers = <Marker>{};
    if (_isCircle && _editCenter != null) {
      markers.add(Marker(position: _editCenter!));
    } else if (!_isCircle) {
      for (final p in _editPoints) {
        markers.add(Marker(position: p));
      }
    }

    return AMapWidget(
      apiKey: AMapApiKey(
        androidKey: AMapConfig.androidKey,
        iosKey: AMapConfig.iosKey,
      ),
      privacyStatement: const AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      ),
      initialCameraPosition: _initialCameraPos,
      onMapCreated: (controller) => _mapController = controller,
      onTap: _onMapTap,
      markers: markers,
      polylines: polylines,
      polygons: polygons,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      rotateGesturesEnabled: true,
    );
  }

  Widget _buildBottomControls() {
    if (_isCircle) {
      return _buildCircleControls();
    }
    return _buildPolygonControls();
  }

  Widget _buildCircleControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.circle_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              const Text('半径: ', style: TextStyle(fontSize: 14)),
              Text('${_editRadius.round()} 米',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: _editRadius,
            min: 50,
            max: 5000,
            divisions: 99,
            label: '${_editRadius.round()} 米',
            onChanged: (v) => setState(() => _editRadius = v),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '围栏名称',
              hintText: '如：公司园区',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 20),
                    label: Text(_saving ? '保存中...' : '保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolygonControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '已选 ${_editPoints.length} 个顶点 (至少3个)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _editPoints.length >= 3 ? Colors.green : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editPoints.isEmpty
                      ? null
                      : () => setState(() => _editPoints.removeLast()),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('撤回'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editPoints.isEmpty
                      ? null
                      : () => setState(() => _editPoints.clear()),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('清空'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '围栏名称',
              hintText: '如：巡逻区域',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 20),
                    label: Text(_saving ? '保存中...' : '保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
