import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget bar(List<Color> colors, {double height = double.infinity}) {
  return Container(
    width: 2,
    height: height,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)],
      ),
    ),
  );
}

void main() {
  testWidgets('ListView 内的时间线条目（Expanded 竖线）布局', (tester) async {
    final g = [const Color(0xFFFFB74D), const Color(0xFFFB8C00), const Color(0xFFE65100)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 34,
                    child: Column(
                      children: [
                        bar(g, height: 6),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: g[2],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                        Expanded(child: bar(g)),
                      ],
                    ),
                  ),
                  const Expanded(child: Padding(padding: EdgeInsets.all(8), child: Text('事件标题'))),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'IntrinsicHeight 修复后不应有 flex 异常');
  });
}
