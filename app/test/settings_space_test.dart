import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wozai_app/pages/settings_page.dart';
import 'package:wozai_app/state/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettings(WidgetTester tester,
      {required List<Map<String, dynamic>> members,
      String? inviteCode,
      String? startDate}) async {
    SharedPreferences.setMockInitialValues({});
    await Session.instance.init();
    Session.instance.user = {'id': 'u1', 'nickname': '我', 'email': 'me@x.com'};
    Session.instance.space = {
      'inviteCode': inviteCode,
      'startDate': startDate,
      'members': members,
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SettingsPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 空间区块在 ListView 下方，滚动到可见
    await tester.scrollUntilVisible(find.text('空间（两人共享）'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  testWidgets('两人空间：显示成员列表、邀请码、无加入按钮', (tester) async {
    await pumpSettings(tester, inviteCode: 'ABC123', members: [
      {'id': 'm1', 'role': 'owner', 'user': {'id': 'u1', 'nickname': '我'}},
      {'id': 'm2', 'role': 'member', 'user': {'id': 'u2', 'nickname': '对方'}},
    ]);

    expect(find.text('空间（两人共享）'), findsOneWidget);
    expect(find.text('对方'), findsOneWidget);
    expect(find.text('创建者（可生成邀请码）'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    // 已满 2 人：不显示邀请码卡片与加入按钮
    expect(find.text('ABC123'), findsNothing);
    expect(find.text('输入邀请码加入空间'), findsNothing);
  });

  testWidgets('一人空间：显示邀请码 + 加入按钮', (tester) async {
    await pumpSettings(tester, inviteCode: 'XYZ789', members: [
      {'id': 'm1', 'role': 'owner', 'user': {'id': 'u1', 'nickname': '我'}},
    ]);

    expect(find.text('XYZ789'), findsOneWidget);
    expect(find.text('输入邀请码加入空间'), findsOneWidget);
    // 自己没标"我"（trailing）
    expect(find.text('我'), findsWidgets);
  });

  testWidgets('单人空间不显示在一起日期', (tester) async {
    await pumpSettings(tester, inviteCode: 'XYZ789', startDate: '2024-05-02T16:00:00.000Z', members: [
      {'id': 'm1', 'role': 'owner', 'user': {'id': 'u1', 'nickname': '我'}},
    ]);
    await tester.scrollUntilVisible(find.text('纪念日（生日 / 毕业日 / 纪念日…）'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('在一起日期'), findsNothing);
  });

  testWidgets('双人空间显示在一起日期', (tester) async {
    await pumpSettings(tester, inviteCode: 'XYZ789', startDate: '2024-05-02T16:00:00.000Z', members: [
      {'id': 'm1', 'role': 'owner', 'user': {'id': 'u1', 'nickname': '我'}},
      {'id': 'm2', 'role': 'member', 'user': {'id': 'u2', 'nickname': '对方'}},
    ]);
    await tester.scrollUntilVisible(find.text('在一起日期'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();

    // 显示日期而非"未设置"（UTC 2024-05-02T16:00Z = 本地 2024-05-03）
    expect(find.textContaining('2024年5月'), findsOneWidget);
    expect(find.textContaining('未设置'), findsNothing);
  });
}
