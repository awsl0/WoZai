import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api/api_client.dart';
import '../utils/city_coords.dart';

/// 搜索结果：名称 + 分层地址 + 坐标（高德式候选）
class _SearchResult {
  const _SearchResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });
  final String name;
  final String address;
  final double lat;
  final double lng;
}

/// 选中的地点结果
class PlaceResult {
  const PlaceResult({required this.name, this.lat, this.lng});
  final String name;
  final double? lat;
  final double? lng;
}

/// 地点选择器：地图选点（可定位）或从历史地点选择
class PlacePickerPage extends StatefulWidget {
  const PlacePickerPage({super.key});

  @override
  State<PlacePickerPage> createState() => _PlacePickerPageState();
}

class _PlacePickerPageState extends State<PlacePickerPage> {
  final MapController _mapController = MapController();
  LatLng? _picked;
  String? _pickedCity;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;
  Timer? _debounce;
  List<_SearchResult> _results = [];
  bool _showResults = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> _historyPlaces = [];
  bool _loadingHistory = true;

  int _mode = 0; // 0 = 地图选点, 1 = 历史地点

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final data = await ApiClient.request('GET', '/api/events');
      final events = (data['events'] as List).cast<Map<String, dynamic>>();
      final names = <String>{};
      for (final e in events) {
        final n = (e['locationName'] as String?)?.trim() ?? '';
        if (n.isNotEmpty) names.add(n);
      }
      if (!mounted) return;
      setState(() {
        _historyPlaces = names.toList()..sort();
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  /// 输入变化：防抖后拉候选列表
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final text = q.trim();
    if (text.isEmpty) {
      setState(() {
        _showResults = false;
        _results = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _searchSuggestions(text));
  }

  /// 候选搜索：优先走自家后端地理编码代理（手机必可达）；失败再降级本地城市库
  Future<void> _searchSuggestions(String q) async {
    setState(() => _searching = true);
    try {
      final data = await ApiClient.request(
          'GET', '/api/geocode?q=${Uri.encodeQueryComponent(q)}');
      final list = (data['results'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _results = [
          for (final r in list)
            _SearchResult(
              name: (r['name'] as String?) ?? q,
              address: (r['address'] as String?) ?? '',
              lat: (r['lat'] as num).toDouble(),
              lng: (r['lng'] as num).toDouble(),
            ),
        ];
        _showResults = true;
        _searching = false;
      });
      return;
    } catch (_) {}
    // 离线兜底：城市库/景点库（网络不可用时仍可定位大城市）
    if (!mounted) return;
    final spot = matchSpot(q);
    final city = matchCity(q);
    setState(() {
      if (spot != null) {
        _results = [
          _SearchResult(name: spot.$1, address: '${spot.$2} · ${spot.$3}', lat: spot.$4, lng: spot.$5),
        ];
      } else if (city != null) {
        _results = [
          _SearchResult(name: city.$2, address: city.$1, lat: city.$3, lng: city.$4),
        ];
      } else {
        _results = [];
      }
      _showResults = true;
      _searching = false;
    });
  }

  /// 回车：直接选中第一个候选（没有候选则用本地城市库/景点库）
  Future<void> _searchSubmit() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty || _searching) return;
    if (_results.isNotEmpty) {
      _selectResult(_results.first);
      return;
    }
    setState(() => _searching = true);
    try {
      final spot = matchSpot(q);
      if (spot != null) {
        _applySearch(spot.$1, LatLng(spot.$4, spot.$5), 13);
        return;
      }
      final city = matchCity(q);
      if (city != null) {
        _applySearch(city.$2, LatLng(city.$3, city.$4), 10);
        return;
      }
      _toast('未找到「$q」，试试输入更完整的地名');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectResult(_SearchResult r) {
    _searchCtrl.text = r.name;
    _searchCtrl.selection = TextSelection.collapsed(offset: r.name.length);
    setState(() {
      _showResults = false;
      _picked = LatLng(r.lat, r.lng);
      _pickedCity = r.name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(LatLng(r.lat, r.lng), 12);
    });
    _toast('已选择：${r.name}${r.address.isEmpty ? '' : '（${r.address}）'}');
  }

  void _applySearch(String name, LatLng p, double zoom) {
    setState(() {
      _showResults = false;
      _picked = p;
      _pickedCity = name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(p, zoom);
    });
    _toast('已定位：$name');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    final city = nearestCity(latlng.latitude, latlng.longitude);
    setState(() {
      _picked = latlng;
      _pickedCity = city;
    });
  }

  void _confirm() {
    if (_picked == null || _pickedCity == null) return;
    Navigator.of(context).pop(PlaceResult(
      name: _pickedCity!,
      lat: _picked!.latitude,
      lng: _picked!.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择地点'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.map_outlined), label: Text('地图选点')),
                ButtonSegment(value: 1, icon: Icon(Icons.history), label: Text('历史地点')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
        ),
      ),
      body: _mode == 0 ? _buildMap(primary) : _buildHistory(primary),
    );
  }

  Widget _buildMap(Color primary) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(34.5, 104.5),
                  initialZoom: 4.5,
                  minZoom: 3,
                  maxZoom: 17,
                  onTap: _onMapTap,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                    subdomains: const ['1', '2', '3', '4'],
                    userAgentPackageName: 'com.wozai.app',
                  ),
                  if (_picked != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _picked!,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                        ),
                      ],
                    ),
                ],
              ),
              // 搜索定位框（输入地名显示候选列表，点击选中定位）
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _searchSubmit(),
                      decoration: InputDecoration(
                        hintText: '搜索地名，如 周口 / 太康县',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.near_me_outlined, size: 20),
                                tooltip: '定位搜索',
                                onPressed: _searchSubmit,
                              ),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.94),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                    ),
                    // 候选列表（高德式）：显示名称 + 分省/市/县地址
                    if (_showResults && _results.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8),
                          ],
                        ),
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => Divider(
                              height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, i) {
                            final r = _results[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined,
                                  size: 18, color: Colors.grey),
                              title: Text(r.name,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: r.address.isEmpty
                                  ? null
                                  : Text(r.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600)),
                              onTap: () => _selectResult(r),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              // 提示
              Positioned(
                top: 72,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('点一下地图选择位置',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 确认条
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _picked == null
                      ? Text('未选择', style: TextStyle(color: Colors.grey.shade600))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📍 $_pickedCity',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              '${_picked!.latitude.toStringAsFixed(4)}, ${_picked!.longitude.toStringAsFixed(4)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                ),
                FilledButton(
                  onPressed: _picked == null ? null : _confirm,
                  style: FilledButton.styleFrom(backgroundColor: primary),
                  child: const Text('使用这个位置'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory(Color primary) {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_historyPlaces.isEmpty) {
      return const Center(
        child: Text('还没有历史地点，用「地图选点」选一个吧', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      itemCount: _historyPlaces.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final name = _historyPlaces[i];
        return ListTile(
          leading: Icon(Icons.place_outlined, color: primary),
          title: Text(name),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => Navigator.of(context).pop(PlaceResult(name: name)),
        );
      },
    );
  }
}
