import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
              // 提示
              Positioned(
                top: 12,
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
