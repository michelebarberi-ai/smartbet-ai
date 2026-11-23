import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/screens/combinations_ai_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('B80: Altri groups selectable observational markets safely',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: CombinationsAiScreen()),
    );
    await tester.pumpAndSettle();

    final altri = find.text('Altri');
    await tester.ensureVisible(altri);
    await tester.tap(altri);
    await tester.pumpAndSettle();

    expect(find.text('Risultato 1° tempo'), findsOneWidget);
    expect(find.text('Risultato 2° tempo'), findsOneWidget);
    expect(find.text('Calci d’angolo'), findsOneWidget);
    expect(find.text('Tiri in porta'), findsOneWidget);

    await tester.ensureVisible(find.text('Risultato 1° tempo'));
    await tester.tap(find.text('Risultato 1° tempo'));
    await tester.pumpAndSettle();
    expect(find.text('1° tempo: X'), findsOneWidget);
    await tester.ensureVisible(find.text('1° tempo: X'));
    await tester.tap(find.text('1° tempo: X'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b79-special-market-mode-explainer')),
        findsOneWidget);
    expect(find.textContaining('ANALIZZA 1T X'), findsOneWidget);
    expect(find.byKey(const Key('b79-no-special-coupon')), findsOneWidget);

    await tester.ensureVisible(find.text('Calci d’angolo'));
    await tester.tap(find.text('Calci d’angolo'));
    await tester.pumpAndSettle();
    expect(find.text('CORNER OVER 8.5'), findsOneWidget);
    await tester.ensureVisible(find.text('CORNER OVER 8.5'));
    await tester.tap(find.text('CORNER OVER 8.5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ANALIZZA CORNER OVER 8.5'), findsOneWidget);

    await tester.ensureVisible(find.text('Tiri in porta'));
    await tester.tap(find.text('Tiri in porta'));
    await tester.pumpAndSettle();
    expect(find.text('TIRI PORTA UNDER 6.5'), findsOneWidget);
    await tester.ensureVisible(find.text('TIRI PORTA UNDER 6.5'));
    await tester.tap(find.text('TIRI PORTA UNDER 6.5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ANALIZZA TIRI PORTA UNDER 6.5'),
        findsOneWidget);

    await tester.ensureVisible(find.text('Risultato partita'));
    await tester.tap(find.text('Risultato partita'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b79-special-market-mode-explainer')),
        findsNothing);
    expect(find.byKey(const Key('b79-no-special-coupon')),
        findsNothing);
  });
}
