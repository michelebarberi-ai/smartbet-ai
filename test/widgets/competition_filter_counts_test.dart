import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/widgets/competition_filter_sheet.dart';

MatchModel testMatch(int id, String country, String league) => MatchModel(
  fixtureId: id,
  homeTeamId: 200 + id,
  awayTeamId: 300 + id,
  homeTeam: 'Casa $id',
  awayTeam: 'Ospite $id',
  league: league,
  leagueId: 0,
  country: country,
  countryCode: '',
  date: '2026-11-20T18:00:00Z',
  leagueType: 'domestic',
  isEuropeanCup: false,
  isFriendly: false,
  isNational: false,
  aiWeight: 0.70,
  smartScore: 60,
  homeWin: 45,
  draw: 30,
  awayWin: 25,
  valueBet: '',
  odd: 0,
);

void main() {
  testWidgets('B66: mostra le partite per campionato e aggiorna il totale',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Set<String>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            saved = await CompetitionFilterSheet.show(
              context: context,
              matches: [
                testMatch(101, 'Italia', 'Serie A'),
                testMatch(102, 'Italia', 'Serie A'),
                testMatch(103, 'Francia', 'Ligue 1'),
              ],
              selectedKeys: const {},
            );
          },
          child: const Text('Apri filtro'),
        )),
      ),
    ));

    await tester.tap(find.text('Apri filtro'));
    await tester.pumpAndSettle();

    expect(find.text('2 partite'), findsWidgets);
    expect(find.text('1 partita'), findsWidgets);
    expect(find.text('PARTITE SELEZIONATE: 3 / 3'), findsOneWidget);
    expect(find.text('APPLICA (2)'), findsOneWidget);

    // Togli Ligue 1: da 3 partite candidate si passa a 2.
    await tester.tap(find.text('Ligue 1').last);
    await tester.pumpAndSettle();
    expect(find.text('PARTITE SELEZIONATE: 2 / 3'), findsOneWidget);
    expect(find.text('APPLICA (1)'), findsOneWidget);

    await tester.tap(find.text('APPLICA (1)'));
    await tester.pumpAndSettle();
    expect(saved, {'Italia|||Serie A'});
  });
}
