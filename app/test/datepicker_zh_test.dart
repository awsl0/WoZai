// 验证日期选择器本地化为中文
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('日期选择器显示中文（确定/取消/星期）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDatePicker(
                context: context,
                initialDate: DateTime(1998, 5, 20),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              ),
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    // 中文界面
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('1998年5月'), findsOneWidget);
    // 不再出现英文 OK/Cancel
    expect(find.text('OK'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    // 星期为中文（单字：日 一 二 三 四 五 六）
    expect(find.text('日'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.text('六'), findsOneWidget);
  });
}
