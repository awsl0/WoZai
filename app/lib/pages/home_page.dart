import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../widgets/event_card.dart';
import 'event_page.dart';
import 'record_page.dart';
import 'settings_page.dart';

/// 主页：时间线 + 顶部“在一起 N 天” + 底部导航
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient.request('GET', '/api/events');
      final events = (data['events'] as List).cast<Map<String, dynamic>>();
      // 同时刷新空间信息（在一起天数）
      final me = await ApiClient.request('GET', '/api/auth/me');
      Session.instance.space = me['space'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() { _events = events; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  String? get _togetherText {
    final start = DateTime.tryParse((Session.instance.space?['startDate'] as String?) ?? '');
    if (start == null) return null;
    final days = DateTime.now().difference(start.toLocal()).inDays + 1;
    final memberCount = (Session.instance.space?['members'] as List?)?.length ?? 1;
    return memberCount > 1 ? '在一起第 $days 天' : '记录第 $days 天';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WoZai 时间线'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _tab == 0 ? _buildTimeline() : const SettingsPage(),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordPage()));
                _refresh();
              },
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('记录此刻'),
              backgroundColor: const Color(0xFFFF6B81),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timeline), label: '时间线'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final together = _togetherText;
    return RefreshIndicator(
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
                  gradient: const LinearGradient(colors: [Color(0xFFFF6B81), Color(0xFFFF9AA8)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(together,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          if (_loading && _events.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
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
                  final month = DateFormat('yyyy年M月').format(
                      DateTime.tryParse((e['happenedAt'] as String?) ?? '')?.toLocal() ?? DateTime.now());
                  final prevMonth = i < _events.length - 1
                      ? DateFormat('yyyy年M月').format(
                          DateTime.tryParse((_events[i + 1]['happenedAt'] as String?) ?? '')?.toLocal() ?? DateTime.now())
                      : null;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (month != prevMonth)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(month,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF6B81))),
                        ),
                      EventCard(event: e, onTap: () => _openEvent(e)),
                    ],
                  );
                },
              ),
            ),
        ],
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
