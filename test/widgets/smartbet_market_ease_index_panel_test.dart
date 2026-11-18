import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_league_market_reliability_service.dart';
import 'package:smartbet_ai_new/services/smartbet_market_ease_index_service.dart';
import 'package:smartbet_ai_new/widgets/smartbet_market_ease_index_panel.dart';

void main() {
  testWidgets('MEI shows missing data as unknown, not zero', (tester) async {
    final report = MarketEaseIndexReport(
      asOf: DateTime.utc(2026, 11, 18),
      evaluatedRecords: 0,
      excludedBeforeReliability: 0,
      entries: const [],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [
        SmartBetMarketEaseIndexPanel(report: report),
      ])),
    ));
    await tester.tap(find.byKey(const Key('b66-mei-panel')));
    await tester.pumpAndSettle();

    expect(find.textContaining('MEI non disponibile'), findsOneWidget);
    expect(find.textContaining('Le quote non sono utilizzate'), findsOneWidget);
  });

  testWidgets('MEI is clearly SHADOW and displays sample size', (tester) async {
    const segment = SmartBetLeagueMarketReliability(
      engine: SmartBetAnalysisEngine.smartBet,
      country: 'Italia',
      league: 'Serie A',
      market: 'GOAL',
      sampleSize: 150,
      correct: 117,
      wrong: 33,
      distinctMatchDays: 60,
      probabilitySampleSize: 150,
      observedAccuracyPercent: 78,
      wilsonLower95Percent: 70.7,
      wilsonUpper95Percent: 83.7,
      averagePredictedPercent: 76,
      calibrationGapPoints: 2,
      brierScore: 0.16,
      evidenceLevel: SmartBetLeagueMarketEvidenceLevel.signal,
    );
    final report = MarketEaseIndexReport(
      asOf: DateTime.utc(2026, 11, 18),
      evaluatedRecords: 150,
      excludedBeforeReliability: 0,
      entries: const [
        MarketEaseIndexEntry(
          evidence: segment,
          status: MarketEaseEvidenceStatus.shadowCandidate,
          score: 72.3,
          brierSkill: 0.1,
          overconfidencePoints: 0,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [
        SmartBetMarketEaseIndexPanel(report: report),
      ])),
    ));
    await tester.tap(find.byKey(const Key('b66-mei-panel')));
    await tester.pumpAndSettle();

    expect(find.textContaining('72.3 / 100'), findsOneWidget);
    expect(find.textContaining('117/150'), findsOneWidget);
    expect(find.textContaining('non autorizza'), findsOneWidget);
  });
}
