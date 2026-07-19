// 电子围栏页面
import 'dart:async';
import 'dart:math' show cos, sin, pi;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import '../config/amap_key.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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
      final List<dynamic> raw = resp.data is List
          ? resp.data
          : (resp.data['data'] ?? resp.data['fences'] ?? []);
      final allFences = raw.cast<Map<String, dynamic>>();

      setState(() {
        if (_isAdmin) {
          _fences = allFences;
        } else {
          _fences = allFences
              .where((f) =>
                  (f['department']?.toString() ?? '') ==
                      (_auth.department ?? '') ||
                  (f['departmentId']?.toString() ?? '') ==
                      (_auth.department ?? ''))
              .toList();
        }
        _fencesLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _fencesLoading = false);
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _eventsLoading = true);
    try {
      final resp = await _api.get('/api/v1/fences/events');
      final List<dynamic> raw = resp.data is List
          ? resp.data
          : (resp.data['data'] ?? resp.data['events'] ?? []);
      setState(() {
        _events = raw.cast<Map<String, dynamic>>();
        _eventsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _eventsLoading = false);
    }
  }

  void _startEventsAutoRefresh() {
    _eventsTimer?.cancel();
    _eventsTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadEvents());
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

  /// 地址搜索 - 调用高德地图地理编码API
  Future<void> _searchAddress() async {
    final keyword = _searchCtrl.text.trim();
    if (keyword.isEmpty) return;
    setState(() => _searchLoading = true);
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://restapi.amap.com/v3/geocode/geo',
        queryParameters: {
          'key': '0e00439a3a2b04282e78083ea7a9b19d',
          'address': keyword,
          'output': 'JSON',
        },
      );
      final geocodes = resp.data['geocodes'] as List?;
      if (geocodes == null || geocodes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到该地址'), backgroundColor: Colors.orange));
        }
        return;
      }
      final location = geocodes[0]['location'] as String? ?? '';
      final parts = location.split(',');
      if (parts.length != 2) throw Exception('坐标格式错误');
      final lng = double.parse(parts[0]);
      final lat = double.parse(parts[1]);
      final address = geocodes[0]['formattedAddress'] as String? ?? keyword;
      if (mounted) {
        setState(() {
          if (_isCircleMode) {
            _circleCenter = LatLng(lat, lng);
            _circleNameCtrl.text = keyword;
          } else {
            _polygonPoints.clear();
            _polygonPoints.add(LatLng(lat, lng));
            _polygonNameCtrl.text = keyword;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已定位到: $address'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _editFence(Map<String, dynamic> fence) async {
    final shapeType = fence['shapeType']?.toString() ?? 'circle';
    final nameCtrl =
        TextEditingController(text: fence['name']?.toString() ?? '');
    final isCircle = shapeType == 'circle';

    // 多边形 - 各顶点编辑
    List<TextEditingController> latCtrls = [];
    List<TextEditingController> lngCtrls = [];
    if (!isCircle) {
      final coords = (fence['coordinates'] as List?) ?? [];
      for (final c in coords) {
        latCtrls.add(TextEditingController(
            text: (c['lat'] as num?)?.toStringAsFixed(6) ?? ''));
        lngCtrls.add(TextEditingController(
            text: (c['lng'] as num?)?.toStringAsFixed(6) ?? ''));
      }
    }

    // 圆形 - 中心/半径
    final latCtrl = isCircle ? TextEditingController(
        text: (fence['centerLat'] as num?)?.toStringAsFixed(6) ?? '') : null;
    final lngCtrl = isCircle ? TextEditingController(
        text: (fence['centerLng'] as num?)?.toStringAsFixed(6) ?? '') : null;
    final radiusCtrl = isCircle ? TextEditingController(
        text: (fence['radiusMeters'] as num?)?.toString() ?? '500') : null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        // 动态添加顶点
        void addPoint() {
          latCtrls.add(TextEditingController(text: ''));
          lngCtrls.add(TextEditingController(text: ''));
          (ctx as dynamic).setState(() {});
        }
        void removePoint(int i) {
          if (latCtrls.length <= 3) return; // 至少3个顶点
          latCtrls[i].dispose();
          lngCtrls[i].dispose();
          latCtrls.removeAt(i);
          lngCtrls.removeAt(i);
          (ctx as dynamic).setState(() {});
        }
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(isCircle ? '编辑圆形围栏' : '编辑多边形围栏'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: '围栏名称', hintText: '如：公司园区')),

                  if (isCircle) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: latCtrl,
                        decoration: const InputDecoration(labelText: '中心纬度'),
                        keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    TextField(
                        controller: lngCtrl,
                        decoration: const InputDecoration(labelText: '中心经度'),
                        keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    TextField(
                        controller: radiusCtrl,
                        decoration: const InputDecoration(labelText: '半径(米)'),
                        keyboardType: TextInputType.number),
                  ] else ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('顶点坐标',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: addPoint,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加', style: TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(latCtrls.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text('${i + 1}.',
                                style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: latCtrls[i],
                                decoration: const InputDecoration(
                                    labelText: '纬度', isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: lngCtrls[i],
                                decoration: const InputDecoration(
                                    labelText: '经度', isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (latCtrls.length > 3)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                                onPressed: () { removePoint(i); setDialogState(() {}); },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final saveData = <String, dynamic>{'name': nameCtrl.text};
                  if (isCircle) {
                    saveData['centerLat'] = double.tryParse(latCtrl?.text ?? '') ?? 0;
                    saveData['centerLng'] = double.tryParse(lngCtrl?.text ?? '') ?? 0;
                    saveData['radiusMeters'] = double.tryParse(radiusCtrl?.text ?? '') ?? 300;
                    saveData['shapeType'] = 'circle';
                  } else {
                    saveData['shapeType'] = 'polygon';
                    saveData['coordinates'] = List.generate(latCtrls.length, (i) => {
                      'lat': double.tryParse(latCtrls[i].text) ?? 0,
                      'lng': double.tryParse(lngCtrls[i].text) ?? 0,
                    });
                  }
                  Navigator.pop(ctx, saveData);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    try {
      await _api.put('/api/v1/fences/${fence['id']}', data: result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('围栏已更新'), backgroundColor: Colors.green));
        _loadFences();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败: $e'), backgroundColor: Colors.red));
      }
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
            content: Text('围栏创建成功'), backgroundColor: Colors.green));
        _circleNameCtrl.clear();
        setState(() {
          _circleCenter = null;
          _circleRadius = 300;
        });
        _loadFences();
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
            content: Text('围栏创建成功'), backgroundColor: Colors.green));
        _polygonNameCtrl.clear();
        setState(() {
          _polygonPoints.clear();
          _polygonComplete = false;
        });
        _loadFences();
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
              ev['address']?.toString() ?? '';
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
        Expanded(child: _buildMapWidget()),
        _buildBottomControls(),
      ],
    );
  }

  /// 地址搜索栏
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
                  hintText: '搜索地址，如：深圳科技园',
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
                            setState(() {});
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _searchAddress(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: _searchLoading ? null : _searchAddress,
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
      initialCameraPosition: const CameraPosition(
        target: LatLng(22.5431, 114.0579), // 深圳
        zoom: 14,
      ),
      onTap: _isCircleMode ? _onCircleMapTap : _onPolygonMapTap,
      markers: markers,
      polylines: polylines,
      polygons: polygons,
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
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _circleSaving ? null : _createCircleFence,
              icon: _circleSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 20),
              label: Text(_circleSaving ? '保存中...' : '保存'),
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
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _polygonSaving ? null : _createPolygonFence,
                icon: _polygonSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 20),
                label: Text(_polygonSaving ? '保存中...' : '保存'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
