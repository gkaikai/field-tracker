/// 公用POI搜索组件
/// 封装高德POI搜索（模糊建议 + 精确搜索 + 地理编码回退）
/// 在 fence_page.dart 和 fence_edit_page.dart 中复用，消除重复代码
library;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/amap_key.dart';
import '../services/api_service.dart';

/// POI搜索结果
class PoiResult {
  final double lat;
  final double lng;
  final String name;
  final String address;

  const PoiResult({
    required this.lat,
    required this.lng,
    required this.name,
    required this.address,
  });
}

/// POI搜索字段组件 — 输入框 + 建议下拉（Stack overlay）
class PoiSearchField extends StatefulWidget {
  /// 选中POI后的回调
  final void Function(PoiResult result) onSelected;

  /// 搜索失败回调（可选）
  final void Function(String message)? onError;

  /// 搜索文字变化回调（可选）
  final void Function(String text)? onTextChanged;

  /// 控制器（外部传入可复用）
  final TextEditingController? controller;

  /// 输入框提示文字
  final String hintText;

  /// 是否支持搜索按钮模式（点击搜索按钮执行精确搜索）
  final bool showSearchButton;

  const PoiSearchField({
    super.key,
    required this.onSelected,
    this.onError,
    this.onTextChanged,
    this.controller,
    this.hintText = '搜索地点',
    this.showSearchButton = true,
  });

  @override
  State<PoiSearchField> createState() => _PoiSearchFieldState();
}

class _PoiSearchFieldState extends State<PoiSearchField> {
  late TextEditingController _ctrl;
  Timer? _debounce;
  List<Map<String, String>> _suggestions = [];
  bool _showSuggestions = false;
  bool _loading = false;
  CancelToken? _cancelToken;

  TextEditingController get controller => _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) _ctrl.dispose();
    _debounce?.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }

  // ──────────────────────────────────────────────
  //  公开方法：外部可调用精确搜索
  // ──────────────────────────────────────────────
  Future<void> searchExact(String keyword) async {
    if (keyword.trim().isEmpty) return;
    // 取消上一次精确搜索的挂起请求
    _cancelToken?.cancel();
    final token = _cancelToken = CancelToken();
    setState(() => _loading = true);
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
        cancelToken: token,
      );

      if (resp.data['status'] != '1') {
        _onError('搜索失败: ${resp.data['info'] ?? '未知错误'}');
        return;
      }

      PoiResult? target;
      final pois = resp.data['pois'] as List?;
      if (pois != null && pois.isNotEmpty) {
        final first = pois[0] as Map<String, dynamic>;
        final location = first['location'] as String? ?? '';
        final parts = location.split(',');
        if (parts.length == 2) {
          final lat2 = double.tryParse(parts[1]);
          final lng2 = double.tryParse(parts[0]);
          if (lat2 != null && lng2 != null) {
            target = PoiResult(
              lat: lat2,
              lng: lng2,
              name: (first['name'] ?? '').toString(),
              address: (first['address'] ?? '').toString(),
            );
          }
        }
      }

      // POI搜不到 → 地理编码回退
      target ??= await _geocodeFallback(keyword);

      if (target == null) {
        _onError('未找到相关地点，试试更具体的关键词（如城市+地点名）');
        return;
      }

      _ctrl.text = target.name;
      setState(() => _showSuggestions = false);
      widget.onSelected(target);
    } on DioException catch (_) {
      // 取消的请求不处理
    } catch (e) {
      _onError('搜索失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ──────────────────────────────────────────────
  //  内部方法
  // ──────────────────────────────────────────────
  void _onSearchChanged(String value) {
    widget.onTextChanged?.call(value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchSuggestions(value.trim());
    });
  }

  Future<void> _fetchSuggestions(String keyword) async {
    // 取消上一次防抖搜索请求，避免竞态
    _cancelToken?.cancel();
    final token = _cancelToken = CancelToken();
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
        cancelToken: token,
      );
      if (resp.data['status'] != '1' || !mounted) {
        setState(() => _showSuggestions = false);
        return;
      }
      final pois = resp.data['pois'] as List?;
      if (pois == null || pois.isEmpty) {
        setState(() => _showSuggestions = false);
        return;
      }
      // 去重：相同 name + location 只保留第一个
      final seen = <String>{};
      final deduped = <Map<String, String>>[];
      for (final t in pois) {
        final m = t as Map<String, dynamic>;
        final name = (m['name'] ?? '').toString();
        final location = (m['location'] ?? '').toString();
        if (location.isEmpty) continue;
        final key = '$name|$location';
        if (seen.contains(key)) continue;
        seen.add(key);
        deduped.add({
          'name': name,
          'address': (m['address'] ?? '').toString(),
          'location': location,
          'district': (m['district'] ?? '').toString(),
        });
      }
      if (!mounted) return;
      setState(() {
        _suggestions = deduped;
        _showSuggestions = deduped.isNotEmpty;
      });
    } on DioException catch (_) {
      // 取消的请求不打印日志
    } catch (_) {
      debugPrint('获取POI建议失败');
    }
  }

  Future<PoiResult?> _geocodeFallback(String keyword) async {
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
              return PoiResult(
                lat: glat,
                lng: glng,
                name: keyword,
                address: geocodes[0]['formatted_address'] as String? ?? keyword,
              );
            }
          }
        }
      }
    } catch (_) {
      debugPrint('地理编码回退失败');
    }
    return null;
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
    _ctrl.text = name;
    widget.onSelected(PoiResult(
      lat: lat,
      lng: lng,
      name: name,
      address: item['address'] ?? '',
    ));
  }

  void _onError(String msg) {
    widget.onError?.call(msg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 搜索栏
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _ctrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _ctrl.clear();
                                setState(() {
                                  _suggestions = [];
                                  _showSuggestions = false;
                                });
                              },
                            )
                          : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            if (widget.showSearchButton) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _loading ? null : () => searchExact(_ctrl.text),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
                  child: const Text('搜索'),
                ),
              ),
            ],
          ],
        ),
        // 建议下拉
        if (_showSuggestions && _suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, i) {
                final item = _suggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(item['name'] ?? '', style: const TextStyle(fontSize: 14)),
                  subtitle: item['address'] != null && item['address']!.isNotEmpty
                      ? Text(item['address']!, style: const TextStyle(fontSize: 11, color: Colors.grey))
                      : null,
                  onTap: () => _onSuggestionTap(item),
                );
              },
            ),
          ),
      ],
    );
  }
}
