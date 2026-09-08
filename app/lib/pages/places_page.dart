import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../utils/city_coords.dart';
import '../widgets/event_card.dart';
import 'event_page.dart';

/// 地点线：旅游踪迹点亮地图 —— 全国按省点亮，点击省份放大看省内城市
class PlacesPage extends StatefulWidget {
  const PlacesPage({super.key});

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

/// 城市聚合点
class _CityAgg {
  _CityAgg(this.province, this.city, this.lat, this.lng);
  final String province;
  final String city;
  final double lat;
  final double lng;
  final List<Map<String, dynamic>> events = [];
  final List<_SpotAgg> spots = []; // 该市内的景点（有景点级记录时）
  int get count => events.length;
  int get spotCount => spots.length;
}

/// 景点/区县聚合点（比城市更细一级）
class _SpotAgg {
  _SpotAgg(this.name, this.city, this.province, this.lat, this.lng);
  final String name;
  final String city;
  final String province;
  final double lat;
  final double lng;
  final List<Map<String, dynamic>> events = [];
  int get count => events.length;
}

/// 省聚合
class _ProvAgg {
  _ProvAgg(this.province, this.lat, this.lng);
  final String province;
  final double lat;
  final double lng;
  final List<_CityAgg> cities = [];
  final List<Map<String, dynamic>> events = []; // 该省全部记录
  int get count => cities.fold(0, (s, c) => s + c.count);
  int get cityCount => cities.length;
}

class _PlacesPageState extends State<PlacesPage> {
  List<Map<String, dynamic>> _events = [];
  List<_CityAgg> _aggs = [];
  List<_SpotAgg> _spotAggs = [];
  List<_ProvAgg> _provAggs = [];
  int _level = 0; // 0=省 1=市 2=景点，根据缩放自动切换
  bool _loading = true;
  bool _unauthorized = false; // 401 未登录时显示「去登录」
  String? _error;
  bool _listMode = false;
  final MapController _mapController = MapController();

  /// 层级切换阈值：zoom < 6 省 / 6-9 市 / ≥9 景点
  static const double _cityZoomThreshold = 6.0;
  static const double _spotZoomThreshold = 9.0;

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
        _unauthorized = e.statusCode == 401;
        _loading = false;
      });
    }
  }

  void _buildAggs() {
    final cityMap = <String, _CityAgg>{};
    final provMap = <String, _ProvAgg>{};
    final spotMap = <String, _SpotAgg>{};

    // 城市坐标查找
    (double, double) cityCoord(String city) {
      for (final c in cityCoords) {
        if (c.$2 == city) return (c.$3, c.$4);
      }
      return (0, 0);
    }

    for (final e in _events) {
      final place = (e['locationName'] as String?)?.trim() ?? '';
      if (place.isEmpty) continue;

      // 1) 先匹配景点/区县（更细一级）
      final spot = matchSpot(place);
      if (spot != null) {
        final sa = spotMap.putIfAbsent(spot.$1,
            () => _SpotAgg(spot.$1, spot.$2, spot.$3, spot.$4, spot.$5));
        sa.events.add(e);
        final cc = cityCoord(spot.$2);
        final ca = cityMap.putIfAbsent(
            '${spot.$3}|${spot.$2}', () => _CityAgg(spot.$3, spot.$2, cc.$1, cc.$2));
        ca.events.add(e);
        if (!ca.spots.contains(sa)) ca.spots.add(sa);
        final pa = provMap.putIfAbsent(spot.$3, () {
          final c = provinceCenters[spot.$3] ?? (cc.$1, cc.$2);
          return _ProvAgg(spot.$3, c.$1, c.$2);
        });
        pa.events.add(e);
        if (!pa.cities.contains(ca)) pa.cities.add(ca);
        continue;
      }

      // 2) 否则匹配城市
      final m = matchCity(place);
      if (m == null) continue;
      final key = '${m.$1}|${m.$2}';
      final agg = cityMap.putIfAbsent(
          key, () => _CityAgg(m.$1, m.$2, m.$3, m.$4));
      agg.events.add(e);
      final pa = provMap.putIfAbsent(m.$1, () {
        final c = provinceCenters[m.$1] ?? (m.$3, m.$4);
        return _ProvAgg(m.$1, c.$1, c.$2);
      });
      pa.events.add(e);
      if (!pa.cities.contains(agg)) pa.cities.add(agg);
    }
    _aggs = cityMap.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    _spotAggs = spotMap.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    _provAggs = provMap.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  }

  /// 点击城市点：放大到城市 + 弹出回忆面板
  void _onCityTap(_CityAgg agg) {
    _mapController.move(LatLng(agg.lat, agg.lng), 10.5);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PlaceSheet(
        title: agg.city,
        subtitle: '${agg.province} · 去过 ${agg.count} 次',
        events: agg.events,
      ),
    );
  }

  /// 地图位置变化：根据缩放级别自动切换 省/市/景点 三级
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    final level = camera.zoom >= _spotZoomThreshold
        ? 2
        : camera.zoom >= _cityZoomThreshold
            ? 1
            : 0;
    if (level != _level) setState(() => _level = level);
  }

  /// 点击省标记：弹出该省所有记录（不再直接放大进下一级）
  void _onProvTap(_ProvAgg prov) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PlaceSheet(
        title: prov.province,
        subtitle: '${prov.cityCount} 个城市 · ${prov.count} 次记录',
        events: prov.events,
      ),
    );
  }

  /// 返回全国（缩小到省层级）
  void _backToChina() {
    _mapController.move(const LatLng(34.5, 104.5), 4.2);
  }

  /// 点击景点标记：放大 + 弹出该景点回忆面板
  void _onSpotTap(_SpotAgg spot) {
    _mapController.move(LatLng(spot.lat, spot.lng), 12);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PlaceSheet(
        title: spot.name,
        subtitle: '${spot.city} · ${spot.count} 次记录',
        events: spot.events,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('地点线'),
        actions: [
          if (_level > 0)
            IconButton(
              icon: const Icon(Icons.public),
              tooltip: '返回全国',
              onPressed: _backToChina,
            ),
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
                      if (_unauthorized)

                        FilledButton(

                          onPressed: () {

                            Session.instance.clear();

                            Navigator.of(context).pushNamedAndRemoveUntil(

                                '/login', (route) => false);

                          },

                          child: const Text('去登录'),

                        )

                      else

                        FilledButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                )
              : _listMode
                  ? _buildList(primary)
                  : _buildMap(primary),
    );
  }

  /// 旅行踪迹：按时间顺序连接去过的地点（优先景点坐标，更精确）
  List<LatLng> _trailPoints() {
    final trail = <LatLng>[];
    final sorted = [..._events]..sort((a, b) {
      final ta = DateTime.tryParse((a['happenedAt'] as String?) ?? '') ?? DateTime(0);
      final tb = DateTime.tryParse((b['happenedAt'] as String?) ?? '') ?? DateTime(0);
      return ta.compareTo(tb);
    });
    for (final e in sorted) {
      final place = (e['locationName'] as String?)?.trim() ?? '';
      if (place.isEmpty) continue;
      final s = matchSpot(place);
      if (s != null) {
        trail.add(LatLng(s.$4, s.$5));
        continue;
      }
      final m = matchCity(place);
      if (m != null) trail.add(LatLng(m.$3, m.$4));
    }
    return trail;
  }

  Widget _buildMap(Color primary) {
    if (_provAggs.isEmpty) {
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

    final trail = _trailPoints();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(34.5, 104.5),
        initialZoom: 4.2,
        minZoom: 3,
        maxZoom: 17,
        backgroundColor: const Color(0xFFE8ECF0),
        onPositionChanged: _onPositionChanged,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
          subdomains: const ['1', '2', '3', '4'],
          userAgentPackageName: 'com.wozai.app',
        ),
        // 旅行踪迹线（按时间先后连接，虚线）
        if (trail.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: trail,
                strokeWidth: 2.5,
                color: primary.withValues(alpha: 0.5),
                pattern: StrokePattern.dashed(segments: [9, 7]),
              ),
            ],
          ),
        // 省层级：省级点亮标记（zoom < 6）
        if (_level == 0)
          MarkerLayer(
            markers: [
              for (final p in _provAggs)
                Marker(
                  point: LatLng(p.lat, p.lng),
                  width: 138,
                  height: 100,
                  alignment: Alignment.topCenter,
                  child: _ProvMarker(
                    prov: p,
                    color: primary,
                    onTap: () => _onProvTap(p),
                  ),
                ),
            ],
          )
        // 市层级：城市点亮标记（6 ≤ zoom < 9）
        else if (_level == 1)
          MarkerLayer(
            markers: [
              for (final agg in _aggs)
                Marker(
                  point: LatLng(agg.lat, agg.lng),
                  width: 132,
                  height: 96,
                  alignment: Alignment.topCenter,
                  child: _GlowMarker(
                    label: agg.city,
                    count: agg.count,
                    color: primary,
                    onTap: () => _onCityTap(agg),
                  ),
                ),
            ],
          )
        // 景点层级：景点点亮标记（zoom ≥ 9，视野外的自然看不见）
        else
          MarkerLayer(
            markers: [
              for (final spot in _spotAggs)
                Marker(
                  point: LatLng(spot.lat, spot.lng),
                  width: 132,
                  height: 96,
                  alignment: Alignment.topCenter,
                  child: _GlowMarker(
                    label: spot.name,
                    count: spot.count,
                    color: primary,
                    onTap: () => _onSpotTap(spot),
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
          if (_provAggs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(
                child: Text('还没有带地点的记录', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            // 省 → 城市 层级
            for (final p in _provAggs)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: primary.withValues(alpha: 0.12),
                    child: Icon(Icons.map_outlined, color: primary, size: 20),
                  ),
                  title: Text(p.province, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${p.cityCount} 个城市 · ${p.count} 次记录',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  children: [
                    for (final agg in p.cities)
                      ExpansionTile(
                        dense: true,
                        tilePadding: const EdgeInsets.only(left: 16, right: 8),
                        leading: Icon(Icons.location_city, color: primary, size: 18),
                        title: Text(agg.city, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          '${agg.count} 次记录${agg.spotCount > 0 ? ' · ${agg.spotCount} 个地点' : ''}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        // 无景点记录时点击直接看城市回忆
                        onExpansionChanged: (_) {},
                        children: [
                          // 该市的景点级记录
                          for (final spot in agg.spots)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.only(left: 40, right: 16),
                              leading: Icon(Icons.tour, color: primary, size: 18),
                              title: Text(spot.name, style: const TextStyle(fontSize: 13)),
                              trailing: Text('${spot.count} 次',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              onTap: () => _onSpotTap(spot),
                            ),
                          // 城市级回忆入口
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 40, right: 16),
                            leading: Icon(Icons.photo_library_outlined, color: primary, size: 18),
                            title: Text('${agg.city}全部回忆', style: const TextStyle(fontSize: 13)),
                            onTap: () => _onCityTap(agg),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// 省点亮标记：光晕 + 省名 + 城市数
class _ProvMarker extends StatefulWidget {
  const _ProvMarker({required this.prov, required this.color, required this.onTap});

  final _ProvAgg prov;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ProvMarker> createState() => _ProvMarkerState();
}

class _ProvMarkerState extends State<_ProvMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);
  late final Animation<double> _pulse =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = widget.prov;
    final color = widget.color;
    final size = 22.0 + (prov.cityCount.clamp(1, 10)) * 2.0;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // 外圈光晕
                  Container(
                    width: size * 2.8 + t * 18,
                    height: size * 2.8 + t * 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.16 * (1 - t * 0.55)),
                    ),
                  ),
                  // 中圈
                  Container(
                    width: size * 1.7,
                    height: size * 1.7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.3),
                    ),
                  ),
                  // 实心点
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.75),
                          blurRadius: 12 + t * 9,
                          spreadRadius: 2 + t * 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${prov.cityCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              '${prov.province}·${prov.cityCount}城',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 点亮标记：呼吸光环 + 实心点（次数）+ 名称标签（城市/景点通用）
class _GlowMarker extends StatefulWidget {
  const _GlowMarker({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_GlowMarker> createState() => _GlowMarkerState();
}

class _GlowMarkerState extends State<_GlowMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);
  late final Animation<double> _pulse =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final count = widget.count;
    final color = widget.color;
    final size = 18.0 + (count.clamp(1, 8)) * 2.5;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 发光点（呼吸动画）
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // 外圈光晕（扩散 + 淡出）
                  Container(
                    width: size * 2.6 + t * 16,
                    height: size * 2.6 + t * 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.16 * (1 - t * 0.55)),
                    ),
                  ),
                  // 中圈
                  Container(
                    width: size * 1.6,
                    height: size * 1.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.28),
                    ),
                  ),
                  // 实心点（发光）
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.75),
                          blurRadius: 10 + t * 8,
                          spreadRadius: 2 + t * 2,
                        ),
                      ],
                    ),
                    child: count > 1
                        ? Center(
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 3),
          // 城市标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 地点回忆面板（城市/景点通用）：标题 + 事件列表
class _PlaceSheet extends StatelessWidget {
  const _PlaceSheet({
    required this.title,
    required this.subtitle,
    required this.events,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final sorted = [...events]..sort((a, b) {
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
              Icon(Icons.place, color: primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$title的回忆', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
