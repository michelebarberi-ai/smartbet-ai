import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/widgets/competition_filter_sheet.dart';

void main() {
  testWidgets('Un preferito preesistente è disponibile anche con il paese Live', (tester) async {
    const storageKey = 'goalvdline.favorite_competition_keys.v1';
    SharedPreferences.setMockInitialValues({
      storageKey: ['Italia|||Serie A', 'Francia|||Ligue 1'],
    });
    Set<String>? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: CompetitionFilterButton(
        leagues: const [('Italy', 'Serie A'), ('Spain', 'La Liga')],
        selectedKeys: const {},
        onChanged: (value) => selected = value,
      ),
    )));
    await tester.tap(find.text('Campionati'));
    await tester.pumpAndSettle();
    expect(find.text('Preferiti (1)'), findsOneWidget);
    await tester.tap(find.text('SOLO PREFERITI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPLICA (1)'));
    await tester.pumpAndSettle();
    expect(selected, {'Italy|||Serie A'});

    await tester.tap(find.text('Campionati'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rimuovi dai preferiti').first);
    await tester.pumpAndSettle();
    expect(find.text('Preferiti (0)'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(storageKey), ['FRANCIA|||ligue 1']);
  });
}
