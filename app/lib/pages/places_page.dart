import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api/api_client.dart';
import '../utils/city_coords.dart';
import '../widgets/event_card.dart';
import 'event_page.dart';

/// 地点线：全国地图点亮去过的地方，点击城市放大查看回忆
class PlacesPage extends StatefulWidget {
  const PlacesPage({super.key});

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

/// 城市聚合点
class _CityAgg {
  _CityAgg(this.city, this.lat, this.lng);
  final String city;
  final double lat;
  final double lng;
  final List<Map<String, dynamic>> events = [];
  int get count => events.length;
}

class _PlacesPageState extends State<PlacesPage> {
  List<Map<String, dynamic>> _events = [];
  List<_CityAgg> _aggs = [];
  bool _loading = true;
  String? _error;
  bool _listMode = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.request('GET', '/api/events');
      final events = (data['events'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _events = events;
        _buildAggs();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _buildAggs() {
    final map = <String, _CityAgg>{};
    for (final e in _events) {
      final place = (e['locationName'] as String?)?.trim() ?? '';
      if (place.isEmpty) continue;
      final m = matchCity(place);
      if (m == null) continue;
      final agg = map.putIfAbsent(m.$1, () => _CityAgg(m.$1, m.$2, m.$3));
      agg.events.add(e);
    }
    final list = map.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    _aggs = list;
  }

  /// 点击城市点：放大到城市 + 弹出回忆面板
  void _onCityTap(_CityAgg agg) {
    _mapController.move(LatLng(agg.lat, agg.lng), 10.5);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CitySheet(agg: agg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('地点线'),
        actions: [
          IconButton(
            icon: Icon(_listMode ? Icons.map_outlined : Icons.view_list_outlined),
            tooltip: _listMode ? '地图模式' : '列表模式',
            onPressed: () => setState(() => _listMode = !_listMode),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: _loading && _events.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                )
              : _listMode
                  ? _buildList(primary)
                  : _buildMap(primary),
    );
  }

  Widget _buildMap(Color primary) {
    if (_aggs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('还没有可点亮的地点', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            const Text('记录时填写地点名（如“天津”），这里会点亮地图', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(34.5, 104.5),
        initialZoom: 4.2,
        minZoom: 3,
        maxZoom: 17,
        backgroundColor: const Color(0xFFE8ECF0),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
          subdomains: const ['1', '2', '3', '4'],
          userAgentPackageName: 'com.wozai.app',
        ),
        MarkerLayer(
          markers: [
            for (final agg in _aggs)
              Marker(
                point: LatLng(agg.lat, agg.lng),
                width: 96,
                height: 56,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => _onCityTap(agg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 圆点（次数多则更大）
                      Container(
                        width: 18.0 + (agg.count.clamp(1, 8)) * 3,
                        height: 18.0 + (agg.count.clamp(1, 8)) * 3,
                        decoration: BoxDecoration(
                          color: primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 6),
                          ],
                        ),
                        child: agg.count > 1
                            ? Center(
                                child: Text('${agg.count}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              )
                            : null,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(agg.city, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildList(Color primary) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (_aggs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(
                child: Text('还没有带地点的记录', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            for (final agg in _aggs)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: primary.withValues(alpha: 0.12),
                    child: Icon(Icons.place, color: primary, size: 20),
                  ),
                  title: Text(agg.city, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('去过 ${agg.count} 次', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onCityTap(agg),
                ),
              ),
        ],
      ),
    );
  }
}

/// 城市回忆面板：该城市的事件列表
class _CitySheet extends StatelessWidget {
  const _CitySheet({required this.agg});
  final _CityAgg agg;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final sorted = [...agg.events]..sort((a, b) {
      final ta = DateTime.tryParse((a['happenedAt'] as String?) ?? '') ?? DateTime(0);
      final tb = DateTime.tryParse((b['happenedAt'] as String?) ?? '') ?? DateTime(0);
      return tb.compareTo(ta);
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Row(
            children: [
              Icon(Icons.location_city, color: primary),
              const SizedBox(width: 8),
              Text(agg.city, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('去过 ${agg.count} 次', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${agg.city}的回忆', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          for (final e in sorted)
            EventCard(
              event: e,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EventPage(eventId: e['id'] as String),
              )),
            ),
        ],
      ),
    );
  }
}
