import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motchiy_todo/screens/auth_gate.dart';

void main() {
  testWidgets('email sign-in can switch to account registration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthGate()));

    expect(find.text('ログイン'), findsOneWidget);
    expect(find.text('メールアドレス'), findsOneWidget);
    expect(find.text('パスワード'), findsOneWidget);

    await tester.tap(find.text('アカウントをお持ちでない方はこちら'));
    await tester.pumpAndSettle();

    expect(find.text('アカウントを作成'), findsOneWidget);
    expect(find.text('表示名'), findsOneWidget);
  });
}
