import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../widgets/event_card.dart';
import 'event_page.dart';

/// 地点线：按地点聚合，显示去过的地方和每个地点的回忆
class PlacesPage extends StatefulWidget {
  const PlacesPage({super.key});

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

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
      if (!mounted) return;
      setState(() {
        _events = (data['events'] as List).cast<Map<String, dynamic>>();
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

  /// 按地点分组：地点名 → 事件列表（时间倒序）。按最近访问时间排序。
  List<(String, List<Map<String, dynamic>>)> get _groups {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in _events) {
      final name = (e['locationName'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => []).add(e);
    }
    final groups = map.entries.toList()
      ..sort((a, b) {
        final ta = DateTime.tryParse((a.value.first['happenedAt'] as String?) ?? '') ?? DateTime(0);
        final tb = DateTime.tryParse((b.value.first['happenedAt'] as String?) ?? '') ?? DateTime(0);
        return tb.compareTo(ta);
      });
    return groups.map((e) => (e.key, e.value)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;

    return Scaffold(
      appBar: AppBar(
        title: const Text('地点线'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading && _events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _events.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Center(
                  child: Column(
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                ),
              )
            else if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.place_outlined, size: 56, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('还没有带地点的记录', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text('记录事件时填上地点，这里会按地点整理回忆', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              for (final (name, events) in groups) _PlaceGroup(name: name, events: events),
          ],
        ),
      ),
    );
  }
}

class _PlaceGroup extends StatefulWidget {
  const _PlaceGroup({required this.name, required this.events});
  final String name;
  final List<Map<String, dynamic>> events;

  @override
  State<_PlaceGroup> createState() => _PlaceGroupState();
}

class _PlaceGroupState extends State<_PlaceGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final last = widget.events.last;
    final lastDate = DateTime.tryParse((last['happenedAt'] as String?) ?? '')?.toLocal();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        leading: CircleAvatar(
          backgroundColor: primary.withValues(alpha: 0.12),
          child: Icon(Icons.place, color: primary, size: 20),
        ),
        title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '去过 ${widget.events.length} 次 · ${lastDate != null ? '最近 ${DateFormat('yyyy年M月').format(lastDate)}' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final e in widget.events)
            EventCard(event: e, onTap: () => _openEvent(e)),
        ],
      ),
    );
  }

  void _openEvent(Map<String, dynamic> event) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventPage(eventId: event['id'] as String),
    ));
  }
}
