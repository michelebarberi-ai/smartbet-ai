import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartbet_ai_new/screens/combinations_ai_screen.dart';

void main() {
  testWidgets('B79: three new families are actual selectable chips',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: CombinationsAiScreen()),
    );
    expect(find.text('Risultato 1° tempo'), findsOneWidget);
    expect(find.text('Risultato 2° tempo'), findsOneWidget);
    expect(find.text('Calci d’angolo'), findsOneWidget);
    expect(find.text('Tiri in porta'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Risultato 1° tempo'), 360);
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

    await tester.scrollUntilVisible(find.text('Calci d’angolo'), 360);
    await tester.tap(find.text('Calci d’angolo'));
    await tester.pumpAndSettle();
    expect(find.text('CORNER OVER 8.5'), findsOneWidget);
    await tester.ensureVisible(find.text('CORNER OVER 8.5'));
    await tester.tap(find.text('CORNER OVER 8.5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ANALIZZA CORNER OVER 8.5'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Tiri in porta'), 360);
    await tester.tap(find.text('Tiri in porta'));
    await tester.pumpAndSettle();
    expect(find.text('TIRI PORTA UNDER 6.5'), findsOneWidget);
    await tester.ensureVisible(find.text('TIRI PORTA UNDER 6.5'));
    await tester.tap(find.text('TIRI PORTA UNDER 6.5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ANALIZZA TIRI PORTA UNDER 6.5'),
      findsOneWidget);

    // Returning to a normal pick restores the ordinary coupon workflow.
    await tester.scrollUntilVisible(find.text('Risultato partita'), -360);
    await tester.tap(find.text('Risultato partita'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b79-special-market-mode-explainer')),
      findsNothing);
    expect(find.byKey(const Key('b79-no-special-coupon')), findsNothing);
  });
}
