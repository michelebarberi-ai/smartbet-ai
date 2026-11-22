import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/personal_coupon_store.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/widgets/personal_coupon_match_tile.dart';

PersonalSelection selection({
  String? country,
  String? league,
  DateTime? kickoffAt,
}) => PersonalSelection(
  fixtureId: '700',
  match: 'Anderlecht - OH Leuven',
  market: 'UNDER 4.5',
  source: 'Crea Schedina',
  probability: 86,
  odds: 1.25,
  bookmaker: 'Betano',
  country: country,
  league: league,
  kickoffAt: kickoffAt,
  capturedAt: DateTime.utc(2026, 11, 22, 11, 20),
);

SmartBetAnalysisRecord history() {
  final kickoff = DateTime.utc(2026, 11, 24, 17);
  return SmartBetAnalysisRecord(
    engine: SmartBetAnalysisEngine.smartBet,
    fixtureId: 700,
    homeTeam: 'Anderlecht',
    awayTeam: 'OH Leuven',
    country: 'Belgio',
    league: 'Jupiler Pro League',
    matchDate: kickoff,
    market: 'UNDER 4.5',
    probability: 0.86,
    smartScore: 84,
    confidence: null,
    classification: null,
    qualified: null,
    sources: const [SmartBetAnalysisSource.aiCoupon],
    prospectiveEligible: true,
    status: SmartBetAnalysisStatus.pending,
    actualHomeGoals: null,
    actualAwayGoals: null,
    firstSeenAt: kickoff.subtract(const Duration(days: 1)),
    lastSeenAt: kickoff.subtract(const Duration(days: 1)),
  );
}

Widget app(PersonalSelection item, {SmartBetAnalysisRecord? archived}) =>
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            PersonalCouponMatchTile(
              selection: item,
              archivedMatch: archived,
              onRemove: () {},
            ),
          ],
        ),
      ),
    );

void main() {
  test('B77: existing coupon JSON stays readable without competition fields',
      () {
    final legacy = PersonalSelection.fromJson({
      'fixtureId': '700',
      'match': 'Anderlecht - OH Leuven',
      'market': 'UNDER 4.5',
      'source': 'Crea Schedina',
      'odds': 1.25,
      'probability': 86,
      'capturedAt': '2026-11-22T11:20:00.000Z',
    });
    expect(legacy.country, isNull);
    expect(legacy.league, isNull);
    expect(legacy.kickoffAt, isNull);
    expect(legacy.match, contains('Anderlecht'));
  });

  test('B77: saved league, country, date and bookmaker survive serialization',
      () {
    final pick = selection(
      country: 'Belgio',
      league: 'Jupiler Pro League',
      kickoffAt: DateTime.utc(2026, 11, 24, 17),
    );
    final restored = PersonalSelection.fromJson(pick.toJson());
    expect(restored.country, 'Belgio');
    expect(restored.league, 'Jupiler Pro League');
    expect(restored.kickoffAt, DateTime.utc(2026, 11, 24, 17));
    expect(restored.bookmaker, 'Betano');
    expect(restored.probability, 86);
    expect(restored.odds, 1.25);
  });

  testWidgets('B77: each saved fixture opens a match details panel',
      (tester) async {
    await tester.pumpWidget(app(selection(
      country: 'Belgio',
      league: 'Jupiler Pro League',
      kickoffAt: DateTime.utc(2026, 11, 24, 17),
    )));
    expect(find.text('Belgio · Jupiler Pro League'), findsOneWidget);
    expect(find.byKey(const Key('personal-match-details')), findsNothing);
    await tester.tap(find.text('Anderlecht - OH Leuven'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('personal-match-details')), findsOneWidget);
    expect(find.text('Scheda della partita'), findsOneWidget);
    expect(find.text('Campionato'), findsOneWidget);
    expect(find.text('Jupiler Pro League'), findsOneWidget);
    expect(find.text('Probabilità AI'), findsOneWidget);
    expect(find.text('Betano'), findsOneWidget);
    expect(find.text('Rimuovi pronostico'), findsOneWidget);
  });

  testWidgets('B77: old pick gets metadata from local history only',
      (tester) async {
    await tester.pumpWidget(app(selection(), archived: history()));
    expect(find.text('Belgio · Jupiler Pro League'), findsOneWidget);
    await tester.tap(find.text('Anderlecht - OH Leuven'));
    await tester.pumpAndSettle();
    expect(find.text('Jupiler Pro League'), findsOneWidget);
  });

  testWidgets('B77: missing competition is explicit, never invented',
      (tester) async {
    await tester.pumpWidget(app(selection()));
    expect(find.text('Paese e campionato non disponibili'), findsOneWidget);
  });
}
