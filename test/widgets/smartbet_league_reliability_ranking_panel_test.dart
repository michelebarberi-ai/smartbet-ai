import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_league_market_reliability_service.dart';
import 'package:smartbet_ai_new/widgets/smartbet_league_reliability_ranking_panel.dart';

SmartBetLeagueMarketReliability segment({
  required String league,
  String market = 'GOAL',
  int sample = 100,
  int days = 20,
  int correct = 80,
  double accuracy = 80,
  double conservative = 70,
}) => SmartBetLeagueMarketReliability(
  engine: SmartBetAnalysisEngine.smartBet,
  country: 'Italia',
  league: league,
  market: market,
  sampleSize: sample,
  correct: correct,
  wrong: sample - correct,
  distinctMatchDays: days,
  probabilitySampleSize: sample,
  observedAccuracyPercent: accuracy,
  wilsonLower95Percent: conservative,
  wilsonUpper95Percent: 99,
  averagePredictedPercent: 75,
  calibrationGapPoints: 5,
  brierScore: 0.2,
  evidenceLevel: sample >= 200
      ? SmartBetLeagueMarketEvidenceLevel.strongShadowCandidate
      : sample >= 100
          ? SmartBetLeagueMarketEvidenceLevel.signal
          : sample >= 50 && days >= 14
              ? SmartBetLeagueMarketEvidenceLevel.exploratory
              : SmartBetLeagueMarketEvidenceLevel.insufficient,
);

SmartBetLeagueMarketReliabilityReport report(
  List<SmartBetLeagueMarketReliability> segments,
) => SmartBetLeagueMarketReliabilityReport(
  asOf: DateTime.utc(2026, 11, 16),
  uniqueEligibleRecords: segments.fold(0, (sum, s) => sum + s.sampleSize),
  skippedUnsafeRecords: 0,
  duplicateRecords: 0,
  conflictingFixtureMarkets: 0,
  segments: segments,
);

Widget app(SmartBetLeagueMarketReliabilityReport report) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [SmartBetLeagueReliabilityRankingPanel(report: report)],
    ),
  ),
);

void main() {
  testWidgets('B62: no data cannot present fake reliable championships',
      (tester) async {
    await tester.pumpWidget(app(report([])));
    await tester.tap(find.byKey(const Key('b62-league-ranking')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('b62-league-ranking-no-evidence')),
      findsOneWidget,
    );
    expect(find.textContaining('Nessuna classifica attendibile'), findsOneWidget);
  });

  testWidgets('B62: rankings use Wilson lower bound, not raw win percentage',
      (tester) async {
    await tester.pumpWidget(app(report([
      segment(
        league: 'Serie A',
        sample: 200,
        correct: 160,
        accuracy: 80,
        conservative: 74,
      ),
      segment(
        league: 'Serie B',
        sample: 50,
        correct: 47,
        accuracy: 94,
        conservative: 64,
      ),
      segment(
        league: 'Serie C',
        sample: 20,
        days: 5,
        correct: 19,
        accuracy: 95,
        conservative: 73,
      ),
    ])));
    await tester.tap(find.byKey(const Key('b62-league-ranking')));
    await tester.pumpAndSettle();

    final first = find.byKey(const Key('b62-league-ranking-row-0'));
    final second = find.byKey(const Key('b62-league-ranking-row-1'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(find.descendant(
      of: first,
      matching: find.textContaining('Serie A'),
    ), findsOneWidget);
    expect(find.descendant(
      of: second,
      matching: find.textContaining('Serie B'),
    ), findsOneWidget);
    expect(find.textContaining('Serie C'), findsNothing);
    expect(find.textContaining('Limite prudenziale 95%: 74.0%'), findsOneWidget);
  });

  testWidgets('B62: market filter keeps different market performance separate',
      (tester) async {
    await tester.pumpWidget(app(report([
      segment(league: 'Serie A', market: 'GOAL'),
      segment(
        league: 'Premier League',
        market: 'OVER 2.5',
        conservative: 75,
      ),
    ])));
    await tester.tap(find.byKey(const Key('b62-league-ranking')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b62-league-ranking-row-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('b62-league-market-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GOAL').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b62-league-ranking-row-0')), findsOneWidget);
    expect(find.byKey(const Key('b62-league-ranking-row-1')), findsNothing);
  });
}
