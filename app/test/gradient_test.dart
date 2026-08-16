import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wozai_app/utils/calendar.dart';

Widget buildBar(List<Color> colors, {double height = double.infinity}) {
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

void main() {
  testWidgets('渐变竖线（Expanded + 固定高度）能渲染', (tester) async {
    final g = timelineGradientOf(8);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  buildBar(g, height: 6),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: monthColorOf(8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                  Expanded(child: buildBar(g)),
                ],
              ),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '渐变竖线不应崩溃');
  });

  testWidgets('月标题渐变节点能渲染', (tester) async {
    final g = timelineGradientOf(8);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: monthColorOf(8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            Container(
              width: 2,
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: g,
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '月标题渐变不应崩溃');
  });
}
