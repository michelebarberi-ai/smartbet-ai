import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartbet_ai_new/screens/combinations_ai_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('B81: all four extra families expose an exclusive all-markets choice',
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
    await tester.pumpWidget(const MaterialApp(home: CombinationsAiScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Altri'));
    await tester.tap(find.text('Altri'));
    await tester.pumpAndSettle();

    final groups = <({String title, String key})>[
      (title: 'Risultato 1° tempo', key: 'b81-all-firstHalf'),
      (title: 'Risultato 2° tempo', key: 'b81-all-secondHalf'),
      (title: 'Calci d’angolo', key: 'b81-all-totalCorners'),
      (title: 'Tiri in porta', key: 'b81-all-totalShotsOnTarget'),
    ];
    for (final group in groups) {
      await tester.ensureVisible(find.text(group.title));
      await tester.tap(find.text(group.title));
      await tester.pumpAndSettle();
      final allButton = find.byKey(Key(group.key));
      expect(allButton, findsOneWidget);
      await tester.ensureVisible(allButton);
      await tester.tap(allButton);
      await tester.pumpAndSettle();

      expect(tester.widget<ChoiceChip>(allButton).selected, isTrue,
          reason: group.title);
      expect(find.byKey(const Key('b81-all-active')), findsOneWidget);
      expect(find.textContaining('TUTTI · OSSERVAZIONE'), findsOneWidget);
      expect(find.textContaining('Nessun mercato selezionato'), findsNothing);
      expect(find.textContaining('non giocabili'), findsWidgets);
    }

    await tester.ensureVisible(find.text('Risultato 1° tempo'));
    await tester.tap(find.text('Risultato 1° tempo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1° tempo: X'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1° tempo: X'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('b81-all-active')), findsNothing);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const Key('b81-all-firstHalf'))).selected, isFalse);
    expect(tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '1° tempo: X')).selected, isTrue);

    await tester.ensureVisible(find.byKey(const Key('b81-all-firstHalf')));
    await tester.tap(find.byKey(const Key('b81-all-firstHalf')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '1° tempo: X')).selected, isFalse);
    expect(find.byKey(const Key('b81-all-active')), findsOneWidget);

    // The normal coupon workflow can be restored.
    await tester.ensureVisible(find.text('Risultato partita'));
    await tester.tap(find.text('Risultato partita'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b81-all-active')), findsNothing);
    expect(tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '1')).selected, isTrue);
  });
}
