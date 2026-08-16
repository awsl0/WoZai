import 'package:flutter_test/flutter_test.dart';
import 'package:wozai_app/utils/calendar.dart';

void main() {
  test('季节色阶函数', () {
    for (var m = 1; m <= 12; m++) {
      final c = monthColorOf(m);
      final g = timelineGradientOf(m);
      final w = isWinterMonth(m);
      // ignore: avoid_print
      print('$m月: color=$c grad=${g.map((x) => x.toARGB32().toRadixString(16)).toList()} winter=$w');
      expect(g.length, 3);
      expect(g[0], isNotNull);
      expect(g[1], isNotNull);
      expect(g[2], isNotNull);
    }
  });

  test('季节图标与文字色', () {
    expect(seasonEmojiOf(3), '🌱');
    expect(seasonEmojiOf(5), '🌱');
    expect(seasonEmojiOf(6), '☀️');
    expect(seasonEmojiOf(8), '☀️');
    expect(seasonEmojiOf(9), '🍂');
    expect(seasonEmojiOf(11), '🍂');
    expect(seasonEmojiOf(12), '❄️');
    expect(seasonEmojiOf(1), '❄️');
    expect(seasonEmojiOf(2), '❄️');
    // 文字色：非冬季应比月色调暗（可读），冬季为蓝灰
    for (var m = 1; m <= 12; m++) {
      final c = textColorOf(m);
      expect(c, isNotNull);
      // 冬季用蓝灰系（蓝色通道 > 红色通道）
      if (isWinterMonth(m)) {
        expect(c.b, greaterThan(c.r), reason: '$m月文字色应有蓝调');
      }
    }
    expect(textColorOf(8).computeLuminance(), lessThan(monthColorOf(8).computeLuminance()),
        reason: '文字色应比月色调暗');
  });
}
