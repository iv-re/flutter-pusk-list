import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat demo: send, delete, burst, jump', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();
    expect(find.text('1000 messages'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Hello there');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hello there', findRichText: true),
      findsOneWidget,
    );

    await tester.longPress(
      find.textContaining('Hello there', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hello there', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burst of 20 messages'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('1020 messages'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
