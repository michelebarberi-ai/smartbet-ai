import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_league_market_reliability_service.dart';
import 'package:smartbet_ai_new/widgets/smartbet_league_market_reliability_panel.dart';

void main() {
  SmartBetLeagueMarketReliabilityReport report(
      List<SmartBetLeagueMarketReliability> segments) =>
    SmartBetLeagueMarketReliabilityReport(
      asOf: DateTime.utc(2026, 11, 13),
      uniqueEligibleRecords: segments.fold(0, (sum, s) => sum + s.sampleSize),
      skippedUnsafeRecords: 0, duplicateRecords: 0,
      conflictingFixtureMarkets: 0,
      segments: segments,
    );

  Widget app(SmartBetLeagueMarketReliabilityReport value) => MaterialApp(
    home: Scaffold(body: ListView(children: [
      SmartBetLeagueMarketReliabilityPanel(report: value),
    ])),
  );

  testWidgets('P21W: no data shows unknown not 0% accuracy', (tester) async {
    await tester.pumpWidget(app(report([])));
    await tester.tap(find.byKey(const Key('p21w-reliability')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('p21w-no-results')), findsOneWidget);
    expect(find.textContaining('affidabilità non determinabile'), findsOneWidget);
  });

  testWidgets('P21W: shows sample counts, uncertainty and not active', (tester) async {
    const sample = SmartBetLeagueMarketReliability(
      engine: SmartBetAnalysisEngine.smartBet,
      country: 'Italia', league: 'Serie A', market: 'GOAL',
      sampleSize: 10, correct: 8, wrong: 2,
      distinctMatchDays: 4, probabilitySampleSize: 10,
      observedAccuracyPercent: 80,
      wilsonLower95Percent: 49, wilsonUpper95Percent: 94.3,
      averagePredictedPercent: 75, calibrationGapPoints: 5,
      brierScore: 0.215,
      evidenceLevel: SmartBetLeagueMarketEvidenceLevel.insufficient,
    );
    await tester.pumpWidget(app(report([sample])));
    await tester.tap(find.byKey(const Key('p21w-reliability')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Italia · Serie A · GOAL'), findsOneWidget);
    expect(find.textContaining('8/10 (80.0%)'), findsOneWidget);
    expect(find.textContaining('49.0%–94.3%'), findsOneWidget);
    expect(find.textContaining('Affidabilità non determinabile'), findsOneWidget);
    expect(find.textContaining('SHADOW'), findsWidgets);
  });
}
