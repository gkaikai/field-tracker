// 电子围栏页面
import 'dart:async';
import 'dart:math' show cos, sin, pi;
import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:dio/dio.dart';
import '../config/amap_key.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:field_tracker/services/amap_location_service.dart';
import 'fence_edit_page.dart';

class FencePage extends StatefulWidget {
  const FencePage({super.key});

  @override
  State<FencePage> createState() => _FencePageState();
}

class _FencePageState extends State<FencePage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  late TabController _tabController;

  // --- 围栏列表 state ---
  List<Map<String, dynamic>> _fences = [];
  bool _fencesLoading = true;

  // --- 进出事件 state ---
  List<Map<String, dynamic>> _events = [];
  bool _eventsLoading = true;
  Timer? _eventsTimer;

  // --- 创建围栏 - map-based state ---
  bool _isCircleMode = true;

  // Circle mode
  LatLng? _circleCenter;
  double _circleRadius = 300;
  final _circleNameCtrl = TextEditingController();
  bool _circleSaving = false;

  // Polygon mode
  final List<LatLng> _polygonPoints = [];
  bool _polygonComplete = false;
  final _polygonNameCtrl = TextEditingController();
  bool _polygonSaving = false;

  // 地址搜索
  final _searchCtrl = TextEditingController();
  bool _searchLoading = false;
  List<Map<String, String>> _searchSuggestions = [];
  bool _showSuggestions = false;
  Timer? _searchDebounce;

  // 地图控制器
  AMapController? _mapController;

  // 地图初始位置
  CameraPosition _initialCameraPos = const CameraPosition(
    target: LatLng(22.5431, 114.0579),
    zoom: 14,
  );

  bool get _isAdmin => _auth.role == 'admin';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isAdmin ? 3 : 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
    _loadFences();
    _loadEvents();
    _startEventsAutoRefresh();
    _initLocation();
  }

  /// 初始化地图位置到当前用户所在位置
  Future<void> _initLocation() async {
    final loc = AmapLocationService();
    double? lat = loc.currentLat;
    double? lng = loc.currentLng;

    // 定位可能还没就绪，等2秒重试
    if (lat == null || lng == null) {
      await Future.delayed(const Duration(seconds: 2));
      lat = loc.currentLat;
      lng = loc.currentLng;
    }

    if (lat != null && lng != null && mounted) {
      final double clat = lat;
      final double clng = lng;
      setState(() {
        _initialCameraPos = CameraPosition(
          target: LatLng(clat, clng),
          zoom: 15,
        );
      });
    }
  }

  @override
  void dispose() {
    _circleNameCtrl.dispose();
    _polygonNameCtrl.dispose();
    _searchCtrl.dispose();
    _eventsTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ===================================================================
  //  API 调用
  // ===================================================================

  Future<void> _loadFences() async {
    setState(() => _fencesLoading = true);
    try {
      final resp = await _api.get('/api/v1/fences');
      final List<dynamic> raw = resp.data is List ? resp.data : (resp.data['fences'] ?? []);
      final allFences = raw.cast<Map<String, dynamic>>();

      setState(() {
        _fences = allFences;
        _fencesLoading = false;
      });
    } catch (e) {
      debugPrint('加载围栏列表失败: $e');
      if (mounted) {
        setState(() => _fencesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载围栏列表失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _loadEvents({bool silent = false}) async {
    if (!silent) setState(() => _eventsLoading = true);
    try {
      final resp = await _api.get('/api/v1/fences/events');
      final raw = (resp.data is Map ? (resp.data['events'] as List? ?? []) : resp.data as List? ?? []);
      setState(() {
        _events = raw.cast<Map<String, dynamic>>();
        _eventsLoading = false;
      });
    } catch (e) {
      debugPrint('加载进出事件失败: $e');
      if (mounted) {
        setState(() => _eventsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载进出事件失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _startEventsAutoRefresh() {
    _eventsTimer?.cancel();
    _eventsTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadEvents(silent: true));
  }

  Future<void> _deleteFence(dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个电子围栏吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.delete('/api/v1/fences/$id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('围栏已删除'), backgroundColor: Colors.green));
        _loadFences();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// 地址搜索 - 调用高德POI搜索API
  /// 输入变化时：防抖搜索建议（改用 place/text 支持模糊搜索）
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

  /// 调用高德POI文本搜索API获取模糊建议列表（替代 inputtips，支持模糊搜索）
  Future<void> _fetchSuggestions(String keyword) async {
    try {
      final dio = Dio();
      final resp = await dio.get(
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
      // 高德API返回 status=0 表示失败
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
          }).where((x) => x['location'] != null && x['location']!.isNotEmpty)
           .toList();
          _showSuggestions = _searchSuggestions.isNotEmpty;
        });
      }
    } catch (_) {
      debugPrint('获取POI建议失败');
    }
  }

  /// 搜索指定关键词并定位到结果第一项
  Future<void> _searchAddress(String keyword) async {
    if (keyword.isEmpty) return;
    setState(() {
      _searchLoading = true;
      _showSuggestions = false;
    });
    try {
      final dio = Dio();
      final resp = await dio.get(
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

      // 高德API状态检查
      if (resp.data['status'] != '1') {
        final info = resp.data['info'] ?? '未知错误';
        debugPrint('[POI搜索] API返回错误: $info');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('搜索失败: $info'), backgroundColor: Colors.orange),
          );
        }
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
              'address': (first['address'] ?? '').toString(),
            };
          }
        }
      }

      // POI搜不到时回退到地理编码（处理纯地址如"深圳市南山区"）
      if (target == null) {
        try {
          final geoResp = await dio.get(
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
                  target = {
                    'lat': glat,
                    'lng': glng,
                    'name': keyword,
                    'address': geocodes[0]['formatted_address'] as String? ?? keyword,
                  };
                }
              }
            }
          }
        } catch (_) {
          debugPrint('地理编码回退失败');
        }
      }

      if (target == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未找到相关地点，试试更具体的关键词（如城市+地点名）'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final lat = target['lat'] as double;
      final lng = target['lng'] as double;
      final name = target['name'] as String;
      final address = target['address'] as String;

      if (mounted) {
        setState(() {
          _searchCtrl.text = name;
          if (_isCircleMode) {
            _circleCenter = LatLng(lat, lng);
            _circleNameCtrl.text = name;
          } else {
            _polygonPoints.clear();
            _polygonComplete = false;
            _polygonPoints.add(LatLng(lat, lng));
            _polygonNameCtrl.text = name;
          }
        });
        _mapController?.moveCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已定位到: ${address.isNotEmpty ? "$name · $address" : name}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _editFence(Map<String, dynamic> fence) async {
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FenceEditPage(fence: fence),
      ),
    );
    if (changed == true && mounted) {
      _loadFences();
    }
  }

  Future<void> _createCircleFence() async {
    if (_circleCenter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请在地图上点击选择围栏中心点'),
            backgroundColor: Colors.orange));
      }
      return;
    }
    final name = _circleNameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请输入围栏名称'), backgroundColor: Colors.orange));
      }
      return;
    }
    setState(() => _circleSaving = true);
    try {
      await _api.post('/api/v1/fences', data: {
        'name': name,
        'shapeType': 'circle',
        'centerLat': _circleCenter!.latitude,
        'centerLng': _circleCenter!.longitude,
        'radiusMeters': _circleRadius,
        'departmentId': null,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('围栏创建成功'),
            backgroundColor: Colors.green));
        _circleNameCtrl.clear();
        setState(() {
          _circleCenter = null;
          _circleRadius = 300;
        });
        await _loadFences();
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _circleSaving = false);
    }
  }

  Future<void> _createPolygonFence() async {
    final name = _polygonNameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请输入围栏名称'), backgroundColor: Colors.orange));
      }
      return;
    }
    if (_polygonPoints.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请至少选取3个顶点'), backgroundColor: Colors.orange));
      }
      return;
    }
    setState(() => _polygonSaving = true);
    try {
      final coords = _polygonPoints
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
      await _api.post('/api/v1/fences', data: {
        'name': name,
        'shapeType': 'polygon',
        'coordinates': coords,
        'departmentId': null,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('围栏创建成功'),
            backgroundColor: Colors.green));
        _polygonNameCtrl.clear();
        setState(() {
          _polygonPoints.clear();
          _polygonComplete = false;
        });
        await _loadFences();
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _polygonSaving = false);
    }
  }

  // ===================================================================
  //  Widget 构建
  // ===================================================================

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(text: '围栏列表'),
      const Tab(text: '进出事件'),
    ];
    if (_isAdmin) {
      tabs.add(const Tab(text: '创建围栏'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('电子围栏'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFenceList(),
          _buildEventsList(),
          if (_isAdmin) _buildCreateFence(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  //  围栏列表 tab
  // -------------------------------------------------------------------
  Widget _buildFenceList() {
    if (_fencesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fences.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fence, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('暂无电子围栏',
                style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 16),
            if (_isAdmin)
              FilledButton.icon(
                onPressed: () => _tabController.animateTo(2),
                icon: const Icon(Icons.add),
                label: const Text('创建围栏'),
              ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFences,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _fences.length,
        itemBuilder: (ctx, i) {
          final f = _fences[i];
          final name = f['name']?.toString() ?? '';
          final department = f['department']?.toString() ??
              f['departmentName']?.toString() ?? '';
          final lat = (f['centerLat'] as num?)?.toStringAsFixed(4) ?? '?';
          final lng = (f['centerLng'] as num?)?.toStringAsFixed(4) ?? '?';
          final radius = f['radiusMeters']?.toString() ?? '?';
          final active = f['status']?.toString() ??
              f['active']?.toString() ??
              'active';
          final isActive =
              active == 'active' || active == 'true' || active == '1';
          final shapeType = f['shapeType']?.toString() ?? 'circle';

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.fence,
                            color: Colors.indigo, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            if (department.isNotEmpty)
                              Text(department,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isActive ? '启用' : '停用',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isActive ? Colors.green : Colors.orange,
                          ),
                        ),
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 20, color: Colors.blue),
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: () => _editFence(f),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: () => _deleteFence(f['id']),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      if (shapeType == 'polygon')
                        Text(
                            '多边形 · ${(f['coordinates'] as List?)?.length ?? 0} 个顶点',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700]))
                      else ...[
                        Text('$lat, $lng',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700])),
                        const SizedBox(width: 16),
                        Icon(Icons.circle_outlined,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('半径 ${radius}m',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700])),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------
  //  进出事件 tab
  // -------------------------------------------------------------------
  Widget _buildEventsList() {
    if (_eventsLoading && _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('暂无进出事件',
                style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 8),
            Text('数据每 10 秒自动刷新',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _events.length,
        itemBuilder: (ctx, i) {
          final ev = _events[i];
          final type = ev['type']?.toString() ??
              ev['eventType']?.toString() ??
              'enter';
          final isEnter =
              type == 'enter' || type == 'entry' || type == 'in';
          final fenceName = ev['fenceName']?.toString() ??
              ev['fence']?.toString() ?? '';
          final time = ev['time']?.toString() ??
              ev['createdAt']?.toString() ?? '';
          final location = ev['location']?.toString() ??
              ev['address']?.toString() ??
              (ev['lat'] != null && ev['lng'] != null
                  ? '${(ev['lat'] as num).toStringAsFixed(5)}, ${(ev['lng'] as num).toStringAsFixed(5)}'
                  : '');
          final accuracy = ev['accuracy'];
          final accuracyText = accuracy != null
              ? '精度: ${(accuracy as num).toStringAsFixed(0)}m'
              : '';
          final userName =
              ev['userName']?.toString() ?? ev['name']?.toString() ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isEnter
                    ? Colors.green.withOpacity(0.15)
                    : Colors.red.withOpacity(0.15),
                child: Icon(
                  isEnter ? Icons.login : Icons.logout,
                  color: isEnter ? Colors.green : Colors.red,
                ),
              ),
              title: Row(
                children: [
                  Text(fenceName,
                      style:
                          const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isEnter
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isEnter ? '进入' : '离开',
                      style: TextStyle(
                          fontSize: 11,
                          color: isEnter ? Colors.green : Colors.red),
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (userName.isNotEmpty)
                    Text('用户: $userName',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  if (time.isNotEmpty)
                    Text(time,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  if (location.isNotEmpty)
                    Text(location,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  if (accuracyText.isNotEmpty)
                    Text(accuracyText,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
                ],
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------
  //  创建围栏 tab — 基于地图的可视化创建（仅管理员可见）
  // -------------------------------------------------------------------
  Widget _buildCreateFence() {
    return Column(
      children: [
        _buildModeToggle(),
        _buildSearchBar(),
        Expanded(
          child: Stack(
            children: [
              _buildMapWidget(),
              // 搜索建议 overlay（在 Column 之外，避免 PlatformView resize 导致触摸丢失）
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
        _buildBottomControls(),
      ],
    );
  }

  /// 搜索建议弹层（独立 widget 用作 Stack overlay，避免 Column 内动态变化 resize 地图）
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
            title: Text(item['name'] ?? '', style: const TextStyle(fontSize: 14)),
            subtitle: item['address'] != null && item['address']!.isNotEmpty
                ? Text(item['address']!, style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            onTap: () {
              _showSuggestions = false;
              final loc = item['location'] ?? '';
              final parts = loc.split(',');
              if (parts.length == 2) {
                final lat = double.tryParse(parts[1]);
                final lng = double.tryParse(parts[0]);
                if (lat != null && lng != null) {
                  final name = item['name'] ?? '';
                  final address = item['address'] ?? '';
                  setState(() {
                    _searchCtrl.text = name;
                    if (_isCircleMode) {
                      _circleCenter = LatLng(lat, lng);
                      _circleNameCtrl.text = name;
                    } else {
                      _polygonPoints.clear();
                      _polygonComplete = false;
                      _polygonPoints.add(LatLng(lat, lng));
                      _polygonNameCtrl.text = name;
                    }
                  });
                  _mapController?.moveCamera(
                    CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已定位到: ${address.isNotEmpty ? "$name · $address" : name}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  _searchAddress(item['name'] ?? '');
                }
              } else {
                _searchAddress(item['name'] ?? '');
              }
            },
          );
        },
      ),
    );
  }

  /// 地址搜索栏（只有一行输入+按钮，不包含建议列表）
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
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索地址，如：郑州科技园',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
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
                onSubmitted: (_) => _searchAddress(_searchCtrl.text.trim()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: _searchLoading ? null : () => _searchAddress(_searchCtrl.text.trim()),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _searchLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 2,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeToggleButton(
              isCircle: true,
              label: '⭕ 圆形',
              selected: _isCircleMode,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _modeToggleButton(
              isCircle: false,
              label: '🔷 多边形',
              selected: !_isCircleMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggleButton({
    required bool isCircle,
    required String label,
    required bool selected,
  }) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _isCircleMode = isCircle;
          _polygonPoints.clear();
          _polygonComplete = false;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue : Colors.grey[200],
        foregroundColor: selected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: selected ? 2 : 0,
      ),
      child: Text(label, style: const TextStyle(fontSize: 15)),
    );
  }

  // --- 计算圆形多边形的辅助点（AMap没有Circle覆盖物，用Polygon近似）---
  List<LatLng> _circlePolygonPoints(LatLng center, double radiusMeters) {
    const n = 64; // 点数越多越圆
    const latPerM = 1.0 / 111320.0;
    final lngPerM = 1.0 /
        (111320.0 * cos(center.latitude * pi / 180.0));
    return List.generate(n, (i) {
      final angle = 2 * pi * i / n;
      return LatLng(
        center.latitude + radiusMeters * cos(angle) * latPerM,
        center.longitude + radiusMeters * sin(angle) * lngPerM,
      );
    });
  }

  Widget _buildMapWidget() {
    // 圆形模式：生成近似圆的polygon覆盖物
    final polygons = <Polygon>{};
    if (_isCircleMode && _circleCenter != null) {
      polygons.add(Polygon(
        points: _circlePolygonPoints(_circleCenter!, _circleRadius),
        strokeWidth: 2,
        strokeColor: Colors.red,
        fillColor: Colors.red.withOpacity(0.15),
      ));
    }

    // 多边形模式：polyline + 闭合时用polygon
    final polylines = <Polyline>{};
    if (!_isCircleMode && _polygonPoints.length >= 2) {
      final pts = _polygonComplete && _polygonPoints.length >= 3
          ? [..._polygonPoints, _polygonPoints.first]
          : List<LatLng>.from(_polygonPoints);
      polylines.add(Polyline(
        points: pts,
        color: Colors.blue,
        width: 3,
      ));
    }
    // 多边形完成时显示填充
    if (!_isCircleMode && _polygonComplete && _polygonPoints.length >= 3) {
      polygons.add(Polygon(
        points: List<LatLng>.from(_polygonPoints),
        strokeWidth: 0,
        fillColor: Colors.blue.withOpacity(0.12),
      ));
    }

    // 标记点
    final markers = <Marker>{};
    if (_isCircleMode && _circleCenter != null) {
      markers.add(Marker(position: _circleCenter!));
    } else if (!_isCircleMode) {
      for (final p in _polygonPoints) {
        markers.add(Marker(position: p));
      }
    }

    return AMapWidget(
      apiKey: const AMapApiKey(
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
      onTap: _isCircleMode ? _onCircleMapTap : _onPolygonMapTap,
      markers: markers,
      polylines: polylines,
      polygons: polygons,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      rotateGesturesEnabled: true,
    );
  }

  void _onCircleMapTap(LatLng latlng) {
    setState(() {
      _circleCenter = latlng;
    });
  }

  void _onPolygonMapTap(LatLng latlng) {
    if (_polygonComplete) return;
    setState(() {
      _polygonPoints.add(latlng);
    });
  }

  Widget _buildBottomControls() {
    if (_isCircleMode) {
      return _buildCircleControls();
    } else {
      return _buildPolygonControls();
    }
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
              const Icon(Icons.circle_outlined,
                  size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              const Text('半径: ', style: TextStyle(fontSize: 14)),
              Text('${_circleRadius.round()} 米',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: _circleRadius,
            min: 50,
            max: 5000,
            divisions: 99,
            label: '${_circleRadius.round()} 米',
            onChanged: (v) => setState(() => _circleRadius = v),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _circleNameCtrl,
            decoration: const InputDecoration(
              labelText: '围栏名称',
              hintText: '如：公司园区',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _circleSaving ? null : _createCircleFence,
                    icon: _circleSaving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 20),
                    label: Text(_circleSaving ? '保存中...' : '保存'),
                  ),
                ),
              ),
            ],
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
              '已选 ${_polygonPoints.length} 个点 (至少3个)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _polygonPoints.length >= 3
                    ? Colors.green
                    : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (!_polygonComplete) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _polygonPoints.isEmpty
                        ? null
                        : () {
                            setState(() => _polygonPoints.removeLast());
                          },
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('撤销上一个点'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _polygonPoints.isEmpty
                        ? null
                        : () {
                            setState(() {
                              _polygonPoints.clear();
                              _polygonComplete = false;
                            });
                          },
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('清空'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _polygonPoints.length >= 3
                        ? () {
                            setState(() => _polygonComplete = true);
                          }
                        : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('完成绘制'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_polygonComplete) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _polygonNameCtrl,
              decoration: const InputDecoration(
                labelText: '围栏名称',
                hintText: '如：巡逻区域',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _polygonSaving ? null : _createPolygonFence,
                      icon: _polygonSaving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, size: 20),
                      label: Text(_polygonSaving ? '保存中...' : '保存'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}