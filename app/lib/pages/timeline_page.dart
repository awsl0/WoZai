import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../utils/calendar.dart';
import 'event_page.dart';

/// 时间线：按年/月归档统计，紧凑条目（日期 + 缩略图 + 标题），点击进详情
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

  /// 按 年 → 月 分组（时间倒序）
  List<MapEntry<int, List<MapEntry<int, List<Map<String, dynamic>>>>>> get _grouped {
    final years = <int, Map<int, List<Map<String, dynamic>>>>{};
    for (final e in _events) {
      final d = DateTime.tryParse((e['happenedAt'] as String?) ?? '')?.toLocal();
      if (d == null) continue;
      years.putIfAbsent(d.year, () => {});
      years[d.year]!.putIfAbsent(d.month, () => []).add(e);
    }
    final yearList = years.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    return yearList.map((y) {
      final months = y.value.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
      return MapEntry(y.key, months);
    }).toList();
  }

  /// 条目标题：备注 → 正文首句 → 地点
  String _titleOf(Map<String, dynamic> e) {
    final note = e['note'] as String?;
    if (note != null && note.isNotEmpty) return note;
    final content = e['content'] as String?;
    if (content != null && content.isNotEmpty) {
      final line = content.replaceAll('\n', ' ').trim();
      return line.length > 40 ? '${line.substring(0, 40)}…' : line;
    }
    final loc = e['locationName'] as String?;
    if (loc != null && loc.isNotEmpty) return loc;
    return '未命名的一天';
  }

  void _openEvent(Map<String, dynamic> event) async {
    final refreshed = await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventPage(eventId: event['id'] as String),
    ));
    if (refreshed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final grouped = _grouped;

    return Scaffold(
      appBar: AppBar(
        title: const Text('时间线'),
        actions: [
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
              : grouped.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera_outlined, size: 56, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('还没有记录', style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 4),
                          Text('点右下角「记录此刻」，拍张照开始吧', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          for (final yearEntry in grouped)
                            _buildYear(theme, primary, yearEntry.key, yearEntry.value),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildYear(
    ThemeData theme,
    Color primary,
    int year,
    List<MapEntry<int, List<Map<String, dynamic>>>> months,
  ) {
    final yearCount = months.fold<int>(0, (sum, m) => sum + m.value.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 年份标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Row(
            children: [
              Text('$year 年',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primary)),
              const SizedBox(width: 8),
              Text('$yearCount 条记录',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 1,
          color: primary.withValues(alpha: 0.2),
        ),
        for (final monthEntry in months) _buildMonth(theme, year, monthEntry.key, monthEntry.value),
      ],
    );
  }

  Widget _buildMonth(
    ThemeData theme,
    int year,
    int month,
    List<Map<String, dynamic>> events,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标题
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
          child: Row(
            children: [
              Text('$month 月', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${events.length} 条',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        for (final e in events) _buildEntry(theme, e),
      ],
    );
  }

  Widget _buildEntry(ThemeData theme, Map<String, dynamic> e) {
    final happened = DateTime.tryParse((e['happenedAt'] as String?) ?? '')?.toLocal();
    final photos = (e['photos'] as List?) ?? [];
    final hasPhoto = photos.isNotEmpty;
    final special = happened != null ? specialDayOf(happened, _startDate) : null;
    final title = _titleOf(e);
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final thumbnailPath = hasPhoto ? (photos.first['filePath'] as String? ?? '') : null;

    return InkWell(
      onTap: () => _openEvent(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            // 日期
            SizedBox(
              width: 44,
              child: Text(
                happened != null ? DateFormat('MM-dd').format(happened) : '',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            // 缩略图（有照片时）
            if (thumbnailPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  '$baseUrl/uploads/${thumbnailPath.split('/').last}',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 40,
                    height: 40,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined, size: 18, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            // 标题 + 特殊日子标记
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                    ),
                  ),
                  if (special != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.celebration_outlined,
                        size: 14, color: theme.colorScheme.primary),
                  ],
                ],
              ),
            ),
            if (!hasPhoto) ...[
              // 无照片：右侧小图标提示点进去
              Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
            ],
          ],
        ),
      ),
    );
  }
}
