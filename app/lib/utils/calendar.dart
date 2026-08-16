/// 节日 / 纪念日 / 农历 / 季度色 工具
library;

import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';

// ---------- 季节渐变颜色（春绿 夏红 秋橙 冬冰雪，按月渐进） ----------
/// 冬季（12-2月）：冰雪蓝白（冰蓝 → 雪白，浅色背景上仍可分辨渐变）
const List<Color> _winterColors = [
  Color(0xFF8FC5E3), // 12月 冰蓝
  Color(0xFFB8DAEE), // 1月 淡冰蓝
  Color(0xFFE6F2F9), // 2月 雪白（淡蓝底）
];
/// 春季（3-5月）：浅绿 → 绿 → 深绿
const List<Color> _springColors = [
  Color(0xFFAED581), // 3月 浅绿
  Color(0xFF66BB6A), // 4月 绿
  Color(0xFF2E7D32), // 5月 深绿
];
/// 夏季（6-8月）：浅红 → 红 → 大红
const List<Color> _summerColors = [
  Color(0xFFEF9A9A), // 6月 浅红
  Color(0xFFEF5350), // 7月 红
  Color(0xFFB71C1C), // 8月 大红
];
/// 秋季（9-11月）：浅橙 → 橙 → 深橙
const List<Color> _autumnColors = [
  Color(0xFFFFB74D), // 9月 浅橙
  Color(0xFFFB8C00), // 10月 橙
  Color(0xFFE65100), // 11月 深橙
];

/// 月份（1-12）归一化
int _normMonth(int month) => ((month - 1) % 12) + 1;

/// 月份所属季节的渐变色三档（浅 → 深）
List<Color> _seasonColors(int m) {
  if (m >= 3 && m <= 5) return _springColors;
  if (m >= 6 && m <= 8) return _summerColors;
  if (m >= 9 && m <= 11) return _autumnColors;
  return _winterColors;
}

/// 月份在季节内的序号（0/1/2，如 3月/6月/9月/12月 = 0）
int _seasonIndex(int m) {
  if (m >= 3 && m <= 5) return m - 3;
  if (m >= 6 && m <= 8) return m - 6;
  if (m >= 9 && m <= 11) return m - 9;
  if (m == 12) return 0;
  if (m == 1) return 1;
  return 2; // 2月
}

/// 某月的季节色（3月浅绿、4月绿、5月深绿…；12月冰蓝、1月淡冰蓝、2月雪白）
Color monthColorOf(int month) {
  final m = _normMonth(month);
  return _seasonColors(m)[_seasonIndex(m)];
}

/// 某月所属季节的渐变三色（浅 → 深，用于时间线左侧竖线渐变）
List<Color> timelineGradientOf(int month) => _seasonColors(_normMonth(month));

/// 是否冬季月份（12-2月，冰雪色系用蓝灰文字/描边保证可读）
bool isWinterMonth(int month) {
  final m = _normMonth(month);
  return m == 12 || m == 1 || m == 2;
}

/// 季节图标（时间线月份节点）：春小草 / 夏太阳 / 秋落叶 / 冬雪花
String seasonEmojiOf(int month) {
  final m = _normMonth(month);
  if (m >= 3 && m <= 5) return '🌱';
  if (m >= 6 && m <= 8) return '☀️';
  if (m >= 9 && m <= 11) return '🍂';
  return '❄️';
}

/// 可读的季节文字色：非冬季 = 月色调暗 28%（浅色也能看清），冬季 = 冰蓝灰
Color textColorOf(int month) {
  final m = _normMonth(month);
  if (isWinterMonth(m)) return const Color(0xFF52748B);
  return Color.lerp(_seasonColors(m)[_seasonIndex(m)], Colors.black, 0.28)!;
}

// ---------- 生肖（按阳历年份） ----------
const Map<String, String> zodiacEmoji = {
  '鼠': '🐭', '牛': '🐮', '虎': '🐯', '兔': '🐰', '龙': '🐲', '蛇': '🐍',
  '马': '🐴', '羊': '🐑', '猴': '🐵', '鸡': '🐔', '狗': '🐶', '猪': '🐷',
};

const List<String> _zodiacNames = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
const List<String> _stems = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const List<String> _branches = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

/// 阳历年份 → 生肖（如 2026 = 马）
String zodiacOf(int year) => _zodiacNames[(year - 4) % 12];

/// 阳历年份 → 干支（如 2026 = 丙午）
String ganzhiOf(int year) {
  final n = year - 4;
  return '${_stems[n % 10]}${_branches[n % 12]}';
}

// ---------- 农历 ----------
/// 阳历日期 → 农历中文（如"七月初七"、"腊月廿三"）
String lunarDateText(DateTime day) {
  final l = Solar.fromDate(day).getLunar();
  return '${l.getMonthInChinese()}月${l.getDayInChinese()}';
}

/// 阳历日期 → 农历月日数字（如 7-7），无则 null
(int, int)? lunarMonthDay(DateTime day) {
  final l = Solar.fromDate(day).getLunar();
  return (l.getMonth(), l.getDay());
}

// ---------- 公历固定节日 ----------
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

// ---------- 纪念日 ----------
String? anniversaryOf(DateTime day, DateTime startDate) {
  final s = DateTime(startDate.year, startDate.month, startDate.day);
  final d = DateTime(day.year, day.month, day.day);
  final days = d.difference(s).inDays + 1;
  if (days < 1) return null;
  if (days % 100 == 0) return '在一起 $days 天';
  if (s.month == d.month && s.day == d.day) {
    final years = d.year - s.year;
    if (years > 0) return '$years 周年纪念日';
  }
  return null;
}

/// 节日名规范化（去掉多余的"节"字，更口语化）
String _normalizeFestival(String name) {
  const map = {'端午节': '端午', '七夕节': '七夕', '中秋节': '中秋', '重阳节': '重阳', '元宵节': '元宵'};
  return map[name] ?? name;
}

/// 某天的特殊日子：阳历节日 → 农历节日 → 纪念日
String? specialDayOf(DateTime day, DateTime? startDate) {
  for (final f in systemFestivals) {
    if (f.$1 == day.month && f.$2 == day.day) return f.$3;
  }
  final lunarFestivals = Solar.fromDate(day).getLunar().getFestivals();
  if (lunarFestivals.isNotEmpty) return _normalizeFestival(lunarFestivals.first);
  if (startDate != null) return anniversaryOf(day, startDate);
  return null;
}

// ---------- 重要节日（用于纪念日提示条目） ----------
const List<(int, int, String)> _notableSolar = [
  (1, 1, '元旦'),
  (2, 14, '情人节'),
  (5, 20, '网络情人节'),
  (10, 1, '国庆节'),
  (12, 24, '平安夜'),
  (12, 25, '圣诞节'),
];

const List<(int, int, String)> _notableLunar = [
  (1, 1, '春节'),
  (1, 15, '元宵节'),
  (5, 5, '端午节'),
  (7, 7, '七夕'),
  (8, 15, '中秋节'),
  (9, 9, '重阳节'),
];

/// 生成某年的"重要节日 + 纪念日"日期列表（用于无事件日的提示条目）
List<(DateTime, String)> notableDaysIn(int year, DateTime? startDate,
    {List<Map<String, dynamic>> customDates = const []}) {
  final result = <(DateTime, String)>[];

  for (final f in _notableSolar) {
    result.add((DateTime(year, f.$1, f.$2), f.$3));
  }
  for (final f in _notableLunar) {
    final solar = Lunar.fromYmd(year, f.$1, f.$2).getSolar();
    result.add((DateTime(solar.getYear(), solar.getMonth(), solar.getDay()), f.$3));
  }

  // DIY 纪念日（生日/毕业日等，每年提醒）
  for (final c in customDates) {
    final m = (c['month'] as num?)?.toInt() ?? 1;
    final d = (c['day'] as num?)?.toInt() ?? 1;
    final name = c['name'] as String? ?? '纪念日';
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      result.add((DateTime(year, m, d), name));
    }
  }

  if (startDate != null) {
    final s0 = DateTime(startDate.year, startDate.month, startDate.day);
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year, 12, 31);
    for (var n = 100; n <= 3650; n += 100) {
      final d = s0.add(Duration(days: n - 1));
      if (!d.isBefore(yearStart) && !d.isAfter(yearEnd)) {
        result.add((DateTime(d.year, d.month, d.day), '在一起 $n 天'));
      }
    }
    for (var y = 1; y <= 50; y++) {
      final d = DateTime(year, s0.month, s0.day);
      if (d.year - s0.year == y) {
        result.add((d, '$y 周年纪念日'));
      }
    }
  }

  // 去重（同一日期保留第一个）
  final seen = <DateTime>{};
  final unique = <(DateTime, String)>[];
  for (final item in result) {
    final key = DateTime(item.$1.year, item.$1.month, item.$1.day);
    if (seen.add(key)) unique.add(item);
  }
  unique.sort((a, b) => a.$1.compareTo(b.$1));
  return unique;
}

// ---------- 即将到来的纪念日/节日 ----------
class UpcomingDay {
  const UpcomingDay(this.name, this.date, this.daysLeft);
  final String name;
  final DateTime date;
  final int daysLeft;
}

UpcomingDay? nextUpcoming(DateTime today, DateTime? startDate,
    {List<Map<String, dynamic>> customDates = const []}) {
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

  // DIY 纪念日（生日/毕业日等）
  for (final c in customDates) {
    final m = (c['month'] as num?)?.toInt() ?? 1;
    final d = (c['day'] as num?)?.toInt() ?? 1;
    final name = c['name'] as String? ?? '纪念日';
    if (m < 1 || m > 12 || d < 1 || d > 31) continue;
    var date = DateTime(today0.year, m, d);
    if (date.isBefore(today0)) date = DateTime(today0.year + 1, m, d);
    consider(name, date);
  }

  for (final f in systemFestivals) {
    var d = DateTime(today0.year, f.$1, f.$2);
    if (d.isBefore(today0)) d = DateTime(today0.year + 1, f.$1, f.$2);
    consider(f.$3, d);
  }
  // 农历重要节日
  for (final f in _notableLunar) {
    var d = Lunar.fromYmd(today0.year, f.$1, f.$2).getSolar();
    var date = DateTime(d.getYear(), d.getMonth(), d.getDay());
    if (date.isBefore(today0)) {
      final next = Lunar.fromYmd(today0.year + 1, f.$1, f.$2).getSolar();
      date = DateTime(next.getYear(), next.getMonth(), next.getDay());
    }
    consider(f.$3, date);
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

// ---------- 在一起天数 ----------
String? togetherText(Map<String, dynamic>? space, {DateTime? now}) {
  final start = DateTime.tryParse((space?['startDate'] as String?) ?? '');
  if (start == null) return null;
  final days = (now ?? DateTime.now()).difference(start.toLocal()).inDays + 1;
  final memberCount = (space?['members'] as List?)?.length ?? 1;
  return memberCount > 1 ? '在一起第 $days 天' : '记录第 $days 天';
}
