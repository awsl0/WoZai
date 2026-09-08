import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../api/api_client.dart';
import '../utils/city_coords.dart';

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

  @override
  void dispose() {
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

  /// 搜索定位：命中后自动选中该位置（可直接确认使用）
  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      // 1) 景点库
      final spot = matchSpot(q);
      if (spot != null) {
        _applySearch(spot.$1, LatLng(spot.$4, spot.$5), 13);
        return;
      }
      // 2) 全国城市库
      final city = matchCity(q);
      if (city != null) {
        _applySearch(city.$2, LatLng(city.$3, city.$4), 10);
        return;
      }
      // 3) Photon 在线地理编码
      final uri = Uri.parse(
          'https://photon.komoot.io/api/?q=${Uri.encodeQueryComponent(q)}&limit=1&lang=zh');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? [];
        if (features.isNotEmpty) {
          final f = features.first as Map<String, dynamic>;
          final coord =
              (((f['geometry'] as Map<String, dynamic>)['coordinates']) as List)
                  .cast<num>();
          if (coord.length >= 2) {
            final name =
                ((f['properties'] as Map<String, dynamic>?)?['name']) ?? q;
            _applySearch(name, LatLng(coord[1].toDouble(), coord[0].toDouble()), 12);
            return;
          }
        }
      }
      _toast('未找到「$q」，试试输入城市名（如 郑州 / 北京）');
    } catch (_) {
      _toast('搜索失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _applySearch(String name, LatLng p, double zoom) {
    setState(() {
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
              // 搜索定位框（输入城市/景点名直接定位并选中）
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: '搜索城市/景点定位，如 郑州',
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
                            onPressed: _search,
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
