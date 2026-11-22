import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_home_league_ranking_panel.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_public_learning_card.dart';

final asOf = DateTime.utc(2026, 11, 22, 20);

SmartBetAnalysisRecord record({
  required int fixture,
  required String league,
  String market = 'GOAL',
  SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
  bool prospective = true,
  bool outcomeKnown = true,
}) {
  final kickoff = DateTime.utc(2026, 7, 1)
      .add(Duration(days: fixture % 90));
  return SmartBetAnalysisRecord(
    engine: engine,
    fixtureId: fixture,
    homeTeam: 'A',
    awayTeam: 'B',
    league: league,
    country: 'Italia',
    matchDate: kickoff,
    market: market,
    probability: 0.7,
    smartScore: 70,
    confidence: null,
    classification: null,
    qualified: null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: prospective,
    status: status,
    actualHomeGoals: 2,
    actualAwayGoals: 1,
    firstSeenAt: kickoff.subtract(const Duration(hours: 4)),
    lastSeenAt: kickoff.add(const Duration(hours: 4)),
    resolvedAt: outcomeKnown
        ? kickoff.add(const Duration(hours: 4)) : null,
  );
}

void main() {
  test('B77: league ranking is prospective, sample-gated and league-deduplicated', () {
    final items = <SmartBetAnalysisRecord>[
      for (var i = 1; i <= 60; i++)
        record(fixture: i, league: 'Serie A',
          status: i <= 40
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong),
      for (var i = 100; i < 150; i++)
        record(fixture: i, league: 'Serie B',
          status: i < 145
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong),
      for (var i = 200; i < 212; i++)
        record(fixture: i, league: 'Serie C'),
      for (var i = 300; i < 360; i++)
        record(fixture: i, league: 'Serie D', prospective: false),
      for (var i = 400; i < 460; i++)
        record(fixture: i, league: 'Premier League', outcomeKnown: false),
      // Second market for one league must not create a duplicate home row.
      for (var i = 500; i < 550; i++)
        record(fixture: i, league: 'Serie B', market: 'OVER 2.5'),
    ];
    final ranking = GoalVdLineHomeLeagueRanking.fromRecords(items, asOf: asOf);

    expect(ranking.established.length, 2);
    expect(ranking.established.first.league, 'Serie B');
    expect(ranking.established.last.league, 'Serie A');
    expect(ranking.observing.map((x) => x.league), contains('Serie C'));
    expect(ranking.established.any((x) => x.league == 'Serie D'), isFalse);
    expect(ranking.established.any((x) => x.league == 'Premier League'), isFalse);
  });

  testWidgets('B77: home visibly shows reliable leagues and their market/engine',
      (tester) async {
    final items = [
      for (var i = 1; i <= 50; i++)
        record(fixture: i, league: 'Serie A',
          status: i <= 39
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLinePublicLearningCard(
            records: items,
            asOf: asOf,
          ),
        ),
      ),
    ));
    expect(find.byKey(const Key('b77-home-league-ranking')), findsOneWidget);
    expect(find.textContaining('Serie A · Italia'), findsOneWidget);
    expect(find.textContaining('39/50 corretti'), findsOneWidget);
    expect(find.textContaining('Limite prudenziale 95%:'), findsOneWidget);
    expect(find.text('Risultati storici e affidabilità'), findsOneWidget);
  });

  testWidgets('B77: small samples are visibly marked as observations',
      (tester) async {
    final items = [
      for (var i = 1; i <= 12; i++)
        record(fixture: i, league: 'Serie C'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineHomeLeagueRankingPanel(
            records: items,
            asOf: asOf,
          ),
        ),
      ),
    ));
    expect(find.byKey(const Key('b77-home-league-observing-warning')),
        findsOneWidget);
    expect(find.textContaining('Serie C · Italia'), findsOneWidget);
    expect(find.textContaining('12/12 corretti'), findsOneWidget);
  });

  testWidgets('B77: no results cannot invent reliable leagues',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: GoalVdLineHomeLeagueRankingPanel(records: []),
      ),
    ));
    expect(find.byKey(const Key('b77-home-league-no-evidence')),
        findsOneWidget);
    expect(find.byKey(const Key('b77-home-league-row-0')),
        findsNothing);
  });
}
