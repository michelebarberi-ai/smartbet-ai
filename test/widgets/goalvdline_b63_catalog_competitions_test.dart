import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/football_competition_catalog_service.dart';
import 'package:smartbet_ai_new/widgets/competition_filter_sheet.dart';

void main() {
  testWidgets('B63: catalog shows leagues even with no fixtures today',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Set<String>? selected;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextButton(
          child: const Text('Seleziona'),
          onPressed: () async {
            selected = await CompetitionFilterSheet.showLeagues(
              context: tester.element(find.text('Seleziona')),
              leagues: const [],
              catalog: const [
                FootballCompetitionCatalogEntry(
                  id: 99, country: 'England', name: 'Premier League', type: 'League'),
                FootballCompetitionCatalogEntry(
                  id: 100, country: 'Spain', name: 'Copa del Rey', type: 'Cup'),
                FootballCompetitionCatalogEntry(
                  id: 101, country: 'World', name: 'Nations League', type: 'Cup'),
              ],
              availabilityCounts: const {'id:101': 4},
              selectedKeys: const {},
            );
          },
        ),
      ),
    ));

    await tester.tap(find.text('Seleziona'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 nel catalogo'), findsOneWidget);
    // L'elenco usa ListView.builder: i campionati fuori viewport sono lazy.
    await tester.scrollUntilVisible(
      find.text('Premier League'), 200,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 40,
    );
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Nessuna partita futura nel periodo selezionato'),
        findsWidgets);

    await tester.tap(find.text('Tutte le competizioni del catalogo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tutte le competizioni del catalogo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPLICA (3)'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });
}
