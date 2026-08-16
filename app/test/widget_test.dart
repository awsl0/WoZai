import 'package:flutter_test/flutter_test.dart';
import 'package:wozai_app/main.dart';

void main() {
  testWidgets('App 能正常构建', (tester) async {
    await tester.pumpWidget(const WozaiApp());
    expect(find.byType(WozaiApp), findsOneWidget);
  });
}
