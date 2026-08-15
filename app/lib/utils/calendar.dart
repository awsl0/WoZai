/// 节日与纪念日工具
library;

/// 公历固定节日（月, 日, 名称）
/// 农历节日（春节/元宵/端午/中秋/七夕等）需农历转换，后续接入 lunar 包
const List<(int, int, String)> systemFestivals = [
  (1, 1, '元旦'),
  (2, 14, '情人节'),
  (3, 8, '妇女节'),
  (5, 1, '劳动节'),
  (5, 20, '网络情人节'),
  (6, 1, '儿童节'),
  (9, 10, '教师节'),
  (10, 1, '国庆节'),
  (11, 11, '双十一'),
  (12, 24, '平安夜'),
  (12, 25, '圣诞节'),
];

/// 某天是哪个公历节日（无则 null）
String? festivalOf(DateTime day) {
  for (final f in systemFestivals) {
    if (f.$1 == day.month && f.$2 == day.day) return f.$3;
  }
  return null;
}

/// 某天是哪个纪念日（基于在一起日期）：100 的倍数天 / 周年
String? anniversaryOf(DateTime day, DateTime startDate) {
  final s = DateTime(startDate.year, startDate.month, startDate.day);
  final d = DateTime(day.year, day.month, day.day);
  final days = d.difference(s).inDays + 1; // 第 N 天
  if (days < 1) return null;
  if (days % 100 == 0) return '在一起 $days 天';
  if (s.month == d.month && s.day == d.day) {
    final years = d.year - s.year;
    if (years > 0) return '$years 周年纪念日';
  }
  return null;
}

/// 事件的"特殊日子"标记：优先节日，其次纪念日
String? specialDayOf(DateTime day, DateTime? startDate) {
  final f = festivalOf(day);
  if (f != null) return f;
  if (startDate != null) return anniversaryOf(day, startDate);
  return null;
}

/// 即将到来的纪念日/节日
class UpcomingDay {
  const UpcomingDay(this.name, this.date, this.daysLeft);
  final String name;
  final DateTime date;
  final int daysLeft;
}

/// 从今天起最近的下一个纪念日/节日（今天的不算）
UpcomingDay? nextUpcoming(DateTime today, DateTime? startDate) {
  final today0 = DateTime(today.year, today.month, today.day);
  UpcomingDay? best;
  void consider(String name, DateTime date) {
    final days = date.difference(today0).inDays;
    if (days <= 0) return;
    final b = best;
    if (b == null) {
      best = UpcomingDay(name, date, days);
    } else if (days < b.daysLeft) {
      best = UpcomingDay(name, date, days);
    }
  }

  for (final f in systemFestivals) {
    var d = DateTime(today0.year, f.$1, f.$2);
    if (d.isBefore(today0)) d = DateTime(today0.year + 1, f.$1, f.$2);
    consider(f.$3, d);
  }

  if (startDate != null) {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final daysTogether = today0.difference(s).inDays + 1;
    if (daysTogether >= 1) {
      final next100 = ((daysTogether ~/ 100) + 1) * 100;
      consider('在一起 $next100 天', today0.add(Duration(days: next100 - daysTogether)));
      var anni = DateTime(today0.year, s.month, s.day);
      if (anni.isBefore(today0)) anni = DateTime(today0.year + 1, s.month, s.day);
      if (!anni.isAtSameMomentAs(today0)) consider('${anni.year - s.year} 周年纪念日', anni);
    }
  }
  return best;
}

/// "在一起第 N 天"文案（双人=在一起，单人=记录）
String? togetherText(Map<String, dynamic>? space, {DateTime? now}) {
  final start = DateTime.tryParse((space?['startDate'] as String?) ?? '');
  if (start == null) return null;
  final days = (now ?? DateTime.now()).difference(start.toLocal()).inDays + 1;
  final memberCount = (space?['members'] as List?)?.length ?? 1;
  return memberCount > 1 ? '在一起第 $days 天' : '记录第 $days 天';
}
