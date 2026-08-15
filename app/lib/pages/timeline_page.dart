import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../utils/calendar.dart';
import '../widgets/event_card.dart';
import 'event_page.dart';

/// 时间线：事件按时间排序 + 节日/纪念日标记
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
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

  DateTime? get _startDate {
    final s = DateTime.tryParse((Session.instance.space?['startDate'] as String?) ?? '');
    return s?.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final together = togetherText(Session.instance.space);

    return Scaffold(
      appBar: AppBar(
        title: const Text('时间线'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (together != null)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [primary, primary.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(together,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ),
            if (_loading && _events.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _events.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                ),
              )
            else if (_events.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('还没有记录', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      const Text('点右下角「记录此刻」，拍张照开始吧', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 88),
                sliver: SliverList.builder(
                  itemCount: _events.length,
                  itemBuilder: (context, i) {
                    final e = _events[i];
                    final happened = DateTime.tryParse((e['happenedAt'] as String?) ?? '')?.toLocal();
                    final month = DateFormat('yyyy年M月').format(happened ?? DateTime.now());
                    final prevHappened = i < _events.length - 1
                        ? DateTime.tryParse((_events[i + 1]['happenedAt'] as String?) ?? '')?.toLocal()
                        : null;
                    final prevMonth = prevHappened != null ? DateFormat('yyyy年M月').format(prevHappened) : null;
                    final special = happened != null ? specialDayOf(happened, _startDate) : null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (month != prevMonth)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(month,
                                style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                          ),
                        if (special != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                            child: _SpecialBadge(label: special, date: happened!),
                          ),
                        EventCard(event: e, onTap: () => _openEvent(e)),
                      ],
                    );
                  },
                ),
              ),
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

/// 节日/纪念日小徽标
class _SpecialBadge extends StatelessWidget {
  const _SpecialBadge({required this.label, required this.date});

  final String label;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_outlined, size: 14, color: primary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(DateFormat('M月d日').format(date),
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
