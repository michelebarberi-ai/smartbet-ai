import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/football_competition_catalog_service.dart';
import 'package:smartbet_ai_new/widgets/competition_filter_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('B76: selection excludes leagues without upcoming games', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Set<String>? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            selected = await CompetitionFilterSheet.showLeagues(
              context: context,
              leagues: const <(String, String)>[],
              catalog: const [
                FootballCompetitionCatalogEntry(
                  id: 135, name: 'Serie A', country: 'Italy', type: 'League',
                ),
                FootballCompetitionCatalogEntry(
                  id: 39, name: 'Premier League', country: 'England',
                  type: 'League',
                ),
                FootballCompetitionCatalogEntry(
                  id: 999, name: 'Serie B', country: 'Italy', type: 'League',
                ),
              ],
              availabilityCounts: const {'id:135': 2, 'id:39': 1},
              selectedKeys: <String>{},
            );
          },
          child: const Text('Apri filtro'),
        )),
      ),
    ));

    await tester.tap(find.text('Apri filtro'));
    await tester.pumpAndSettle();
    expect(find.text('PARTITE SELEZIONATE: 3 / 3'), findsOneWidget);
    // Catalog is a lazy list: scroll to the disabled league before reading it.
    await tester.scrollUntilVisible(find.text('Serie B'), 150,
      scrollable: find.byType(Scrollable).last, maxScrolls: 40,
    );
    final noGames = tester.widget<CheckboxListTile>(find.ancestor(
      of: find.text('Serie B'),
      matching: find.byType(CheckboxListTile),
    ));
    expect(noGames.onChanged, isNull);

    // Select one league, rather than a zero-match catalog entry.
    await tester.tap(find.text('Tutte le competizioni del catalogo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Serie A'), -150,
      scrollable: find.byType(Scrollable).last, maxScrolls: 40,
    );
    // The sheet footer can cover the row's tap target on small test screens.
    // Invoke the checkbox action after locating its built widget.
    final serieA = tester.widget<CheckboxListTile>(find.ancestor(
      of: find.text('Serie A'),
      matching: find.byType(CheckboxListTile),
    ));
    expect(serieA.onChanged, isNotNull);
    serieA.onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.text('PARTITE SELEZIONATE: 2 / 3'), findsOneWidget);
    await tester.tap(find.text('APPLICA (1)'));
    await tester.pumpAndSettle();
    expect(selected, {'id:135'});
  });
}
