import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../utils/calendar.dart';
import '../widgets/event_card.dart';
import 'event_page.dart';

/// 主页：在一起天数 + 下一个纪念日 + 统计 + 最近记录
class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key, this.onViewAll});

  /// “查看全部”点击回调（切到时间线 tab）
  final VoidCallback? onViewAll;

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
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
      final events = (data['events'] as List).cast<Map<String, dynamic>>();
      final me = await ApiClient.request('GET', '/api/auth/me');
      Session.instance.space = me['space'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _events = events;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final space = Session.instance.space;
    final together = togetherText(space);
    final startDate = DateTime.tryParse((space?['startDate'] as String?) ?? '')?.toLocal();
    final upcoming = nextUpcoming(DateTime.now(), startDate);
    final me = Session.instance.user;

    // 统计
    final placeNames = _events
        .map((e) => e['locationName'] as String?)
        .where((n) => n != null && n.isNotEmpty)
        .toSet();
    final photoCount = _events.fold<int>(0, (sum, e) => sum + ((e['photos'] as List?)?.length ?? 0));
    final recent = _events.take(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('WoZai'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // 在一起天数大卡片
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        child: Icon(Icons.favorite, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        together ?? (me?['nickname'] as String? ?? '我的记录'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    upcoming != null ? '还有 ${upcoming.daysLeft} 天 · ${upcoming.name}' : '记录每一天',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('yyyy年M月d日').format(DateTime.now()),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 统计
            Row(
              children: [
                _StatCard(icon: Icons.event_note, value: '${_events.length}', label: '记录'),
                const SizedBox(width: 10),
                _StatCard(icon: Icons.place_outlined, value: '${placeNames.length}', label: '去过的地方'),
                const SizedBox(width: 10),
                _StatCard(icon: Icons.photo_outlined, value: '$photoCount', label: '照片'),
              ],
            ),
            if (_loading && _events.isEmpty) ...[
              const SizedBox(height: 32),
              const Center(child: CircularProgressIndicator()),
            ] else if (_error != null && _events.isEmpty) ...[
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: _refresh, child: const Text('重试')),
                  ],
                ),
              ),
            ] else if (_events.isEmpty) ...[
              const SizedBox(height: 48),
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.photo_camera_outlined, size: 56, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('还没有记录，点右下角「记录此刻」开始吧', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              const Text('最近记录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              for (final e in recent)
                EventCard(event: e, onTap: () => _openEvent(e)),
              if (_events.length > 3)
                Center(
                  child: TextButton(
                    onPressed: widget.onViewAll,
                    child: const Text('查看全部 →'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _openEvent(Map<String, dynamic> event) async {
    final refreshed = await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventPage(eventId: event['id'] as String),
    ));
    if (refreshed == true) _refresh();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: primary, size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
