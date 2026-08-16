import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../utils/calendar.dart';
import '../utils/weather.dart';
import 'event_page.dart';

/// 时间线：左侧时间轴串联 + 季度渐变色 + 年度生肖图表 + 节日/纪念日提示 + 阴/阳历切换
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

/// 混合条目：事件 或 节日/纪念日提示
class _Entry {
  _Entry.event(this.date, this.event) : notice = null;
  _Entry.notice(this.date, this.notice) : event = null;

  final DateTime date;
  final Map<String, dynamic>? event;
  final String? notice;
  bool get isEvent => event != null;
}

class _TimelinePageState extends State<TimelinePage> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _unauthorized = false; // 401 未登录时显示「去登录」
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
        _unauthorized = e.statusCode == 401;
        _loading = false;
      });
    }
  }

  DateTime? get _startDate {
    final s = DateTime.tryParse((Session.instance.space?['startDate'] as String?) ?? '');
    return s?.toLocal();
  }

  /// DIY 纪念日（按归属拼显示名：我的生日 / 小E的生日 / 共同）
  List<Map<String, dynamic>> get _customDates => displayCustomDates(
      (Session.instance.space?['customDates'] as List?) ?? const [],
      Session.instance.user,
      Session.instance.space?['members'] as List? ?? const []);

  /// 生成混合条目（事件 + 无记录日期的节日/纪念日提示）
  List<_Entry> get _entries {
    final list = <_Entry>[];
    for (final e in _events) {
      final d = DateTime.tryParse((e['happenedAt'] as String?) ?? '')?.toLocal();
      if (d == null) continue;
      list.add(_Entry.event(DateTime(d.year, d.month, d.day), e));
    }
    // 提示条目：事件覆盖到的年份范围 + 今年（仅显示到今天为止的，不预告未来）
    final years = list.map((x) => x.date.year).toSet();
    years.add(DateTime.now().year);
    final eventDates = list.map((x) => x.date).toSet();
    final today = DateTime.now();
    for (final y in years) {
      for (final (d, name) in notableDaysIn(y, _startDate, customDates: _customDates)) {
        // 跳过与事件重叠的日期，以及未来的节日/纪念日（避免时间线提前出现国庆等）
        if (!eventDates.contains(d) && !d.isAfter(today)) list.add(_Entry.notice(d, name));
      }
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// 年 → 月 分组
  List<MapEntry<int, List<MapEntry<int, List<_Entry>>>>> _group(List<_Entry> entries) {
    final years = <int, Map<int, List<_Entry>>>{};
    for (final e in entries) {
      years.putIfAbsent(e.date.year, () => {});
      years[e.date.year]!.putIfAbsent(e.date.month, () => []).add(e);
    }
    final yearList = years.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    return yearList.map((y) {
      final months = y.value.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
      return MapEntry(y.key, months);
    }).toList();
  }

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

  /// 日期文本（按历法）
  /// 日期文本：阳历在上、阴历在下（两行）
  String _dateText(DateTime d) => '${DateFormat('MM-dd').format(d)}\n${lunarDateText(d)}';

  void _openEvent(Map<String, dynamic> event) async {
    final refreshed = await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventPage(eventId: event['id'] as String),
    ));
    if (refreshed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;
    final grouped = _group(entries);

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
                            _YearSection(
                              year: yearEntry.key,
                              months: yearEntry.value,
                              theme: theme,
                              dateText: _dateText,
                              titleOf: _titleOf,
                              onTapEvent: _openEvent,
                            ),
                        ],
                      ),
                    ),
    );
  }
}

/// 一年：生肖卡片 + 月份分组
class _YearSection extends StatelessWidget {
  const _YearSection({
    required this.year,
    required this.months,
    required this.theme,
    required this.dateText,
    required this.titleOf,
    required this.onTapEvent,
  });

  final int year;
  final List<MapEntry<int, List<_Entry>>> months;
  final ThemeData theme;
  final String Function(DateTime) dateText;
  final String Function(Map<String, dynamic>) titleOf;
  final void Function(Map<String, dynamic>) onTapEvent;

  @override
  Widget build(BuildContext context) {
    final eventCount = months.fold<int>(
        0, (sum, m) => sum + m.value.where((e) => e.isEvent).length);
    final noticeCount = months.fold<int>(
        0, (sum, m) => sum + m.value.where((e) => !e.isEvent).length);
    final photoCount = months.fold<int>(0, (sum, m) {
      var n = sum;
      for (final e in m.value) {
        if (e.event != null) n += ((e.event!['photos'] as List?)?.length ?? 0);
      }
      return n;
    });
    final monthColor = monthColorOf(DateTime.now().month);
    final isWinter = isWinterMonth(DateTime.now().month);
    final cardColor = isWinter ? Colors.blueGrey.shade300 : monthColor;
    final zodiac = zodiacOf(year);
    final ganzhi = ganzhiOf(year);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 年度生肖图表卡片
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cardColor.withValues(alpha: 0.25), cardColor.withValues(alpha: 0.05)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cardColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Text(zodiacEmoji[zodiac] ?? '📅',
                  style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$ganzhi$zodiac年 · $year',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      '$eventCount 条记录 · $photoCount 张照片'
                      '${noticeCount > 0 ? ' · $noticeCount 个纪念日' : ''}',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 月份
        for (final monthEntry in months)
          _MonthSection(
            month: monthEntry.key,
            entries: monthEntry.value,
            theme: theme,
            dateText: dateText,
            titleOf: titleOf,
            onTapEvent: onTapEvent,
          ),
      ],
    );
  }
}

/// 一个月：标题 + 条目（含时间线节点）
class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.month,
    required this.entries,
    required this.theme,
    required this.dateText,
    required this.titleOf,
    required this.onTapEvent,
  });

  final int month;
  final List<_Entry> entries;
  final ThemeData theme;
  final String Function(DateTime) dateText;
  final String Function(Map<String, dynamic>) titleOf;
  final void Function(Map<String, dynamic>) onTapEvent;

  @override
  Widget build(BuildContext context) {
    final color = monthColorOf(month);
    final gradientColors = timelineGradientOf(month);
    final eventCount = entries.where((e) => e.isEvent).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标题（时间线节点：季节图标）
        Row(
          children: [
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  Text(seasonEmojiOf(month), style: const TextStyle(fontSize: 16)),
                  Container(
                    width: 2,
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: gradientColors,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text('$month 月', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColorOf(month))),
                  const SizedBox(width: 6),
                  Text('$eventCount 条',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        for (final e in entries) _EntryRow(
          entry: e,
          monthColor: color,
          theme: theme,
          dateText: dateText,
          titleOf: titleOf,
          onTapEvent: onTapEvent,
        ),
      ],
    );
  }
}

/// 单条：左侧时间线 + 内容
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.monthColor,
    required this.theme,
    required this.dateText,
    required this.titleOf,
    required this.onTapEvent,
  });

  final _Entry entry;
  final Color monthColor;
  final ThemeData theme;
  final String Function(DateTime) dateText;
  final String Function(Map<String, dynamic>) titleOf;
  final void Function(Map<String, dynamic>) onTapEvent;

  /// 季节渐变的竖线（上浅 → 下深）
  Widget _bar(List<Color> colors, {double height = double.infinity}) {
    return Container(
      width: 2,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWinter = isWinterMonth(entry.date.month);
    final gradientColors = timelineGradientOf(entry.date.month);
    final dotBorder = isWinter ? Colors.blueGrey.shade400 : Colors.white;
    final noticeColor = textColorOf(entry.date.month);

    if (!entry.isEvent) {
      // 节日/纪念日提示条目
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  _bar(gradientColors, height: 4),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isWinter ? Colors.blueGrey.shade400 : monthColor, width: 1.5),
                      color: Colors.transparent,
                    ),
                  ),
                  Expanded(child: _bar(gradientColors)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.celebration_outlined, size: 14, color: noticeColor),
                    const SizedBox(width: 6),
                    Text(
                      '${DateFormat('MM-dd').format(entry.date)} · ${lunarDateText(entry.date)} · ${entry.notice}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: noticeColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 事件条目
    final e = entry.event!;
    final photos = (e['photos'] as List?) ?? [];
    final hasPhoto = photos.isNotEmpty;
    final title = titleOf(e);
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final thumbnailPath = hasPhoto ? (photos.first['filePath'] as String? ?? '') : null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                _bar(gradientColors, height: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: monthColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotBorder, width: 2),
                  ),
                ),
                Expanded(child: _bar(gradientColors)),
              ],
            ),
          ),
        Expanded(
          child: InkWell(
            onTap: () => onTapEvent(e),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 日期（季节色，稍淡）
                  SizedBox(
                    width: 52,
                    child: Text(
                      dateText(entry.date),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: noticeColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  // 缩略图
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
                  // 标题（季节色）+ 天气
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: noticeColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // 天气（记录时按日期+地点获取）
                        if (e['weather'] != null) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wb_sunny_outlined,
                                  size: 12, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(
                                '${e['weather']?['text'] ?? ''}'
                                '${e['weather']?['temp'] != null ? ' ${e['weather']?['temp']}' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!hasPhoto)
                    Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}
