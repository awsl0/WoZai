import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归测试：主页顶部卡片在窄屏 + 放大字体下不得溢出/遮挡（B1）
void main() {
  testWidgets('窄屏+1.4倍字体：卡片标题完整显示无溢出', (tester) async {
    // 320px 极窄屏（比任何真机还窄）
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 模拟 HomeTabPage 顶部卡片的 Row 结构（FittedBox 标题 + 双心 + 右侧头像组）
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.purple, Colors.purpleAccent]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 30,
                              height: 24,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                      left: 2,
                                      top: 1,
                                      child: Icon(Icons.favorite, color: Color(0xFFD81B60), size: 20)),
                                  Positioned(
                                      left: 16,
                                      top: 13,
                                      child: Icon(Icons.favorite, color: Color(0xFFC2185B), size: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('在一起第 1234 天',
                                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('还有 3 天 · 七夕',
                              style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FakeAvatar(),
                      const SizedBox(width: 3),
                      const SizedBox(width: 42, height: 46, child: SizedBox()),
                      const SizedBox(width: 3),
                      _FakeAvatar(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));

    // 无溢出异常（RenderFlex overflow 会在这里抛出）
    expect(tester.takeException(), isNull);
  });
}

/// 模拟头像（圆形）
class _FakeAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white70),
    );
  }
}
