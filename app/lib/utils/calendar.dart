/// 节日 / 纪念日 / 农历 / 季度色 工具
library;

import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';

// ---------- 季度渐变颜色（春绿 夏红 秋黄 冬白，月份间过渡） ----------
const List<Color> monthColors = [
  Color(0xFFECEFF1), // 1月 冬白
  Color(0xFFC5E1A5), // 2月 冬→春
  Color(0xFF66BB6A), // 3月 春绿
  Color(0xFF43A047), // 4月 春深绿
  Color(0xFFAED581), // 5月 春→夏
  Color(0xFFEF5350), // 6月 夏红
  Color(0xFFE53935), // 7月 夏深红
  Color(0xFFFF7043), // 8月 夏→秋
  Color(0xFFFFC107), // 9月 秋黄
  Color(0xFFFFB300), // 10月 秋深黄
  Color(0xFFBCAAA4), // 11月 秋→冬
  Color(0xFFECEFF1), // 12月 冬白
];

Color monthColorOf(int month) => monthColors[(month - 1) % 12];

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
List<(DateTime, String)> notableDaysIn(int year, DateTime? startDate) {
  final result = <(DateTime, String)>[];

  for (final f in _notableSolar) {
    result.add((DateTime(year, f.$1, f.$2), f.$3));
  }
  for (final f in _notableLunar) {
    final solar = Lunar.fromYmd(year, f.$1, f.$2).getSolar();
    result.add((DateTime(solar.getYear(), solar.getMonth(), solar.getDay()), f.$3));
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
