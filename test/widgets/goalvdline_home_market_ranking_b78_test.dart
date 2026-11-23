import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_home_market_ranking_panel.dart';

SmartBetAnalysisRecord record(int index) {
  final kickoff = DateTime.utc(2026, 4, 1).add(Duration(days: index));
  return SmartBetAnalysisRecord(
    engine: SmartBetAnalysisEngine.smartBet,
    fixtureId: 1000 + index,
    homeTeam: 'Casa', awayTeam: 'Ospite',
    country: 'Italia', league: 'Serie A',
    matchDate: kickoff,
    market: 'UNDER 4.5',
    probability: 0.76,
    smartScore: 76,
    confidence: null, classification: null, qualified: null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: true,
    status: index % 5 == 0
        ? SmartBetAnalysisStatus.wrong
        : SmartBetAnalysisStatus.correct,
    actualHomeGoals: 2,
    actualAwayGoals: index % 5 == 0 ? 3 : 1,
    firstSeenAt: kickoff.subtract(const Duration(hours: 8)),
    lastSeenAt: kickoff.add(const Duration(hours: 5)),
    resolvedAt: kickoff.add(const Duration(hours: 5)),
  );
}

void main() {
  testWidgets('B78: home market leader is explicitly unavailable for small sample',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineHomeMarketRankingPanel(
            records: [for (var i = 0; i < 15; i++) record(i)],
            asOf: DateTime.utc(2026, 11, 23),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Mercati storicamente più affidabili'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b78-home-no-market-leader')),
      findsOneWidget);
  });

  testWidgets('B78: home ranks verified market and engine with MEI and sample',
      (tester) async {
    final records = [for (var i = 0; i < 120; i++) record(i)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineHomeMarketRankingPanel(
            records: records,
            asOf: DateTime.utc(2026, 11, 23),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Mercati storicamente più affidabili'));
    await tester.pumpAndSettle();
    expect(find.textContaining('UNDER 4.5 · SmartBet'), findsOneWidget);
    expect(find.textContaining('MEI '), findsOneWidget);
    expect(find.textContaining('120 corretti'), findsNothing);
    expect(find.textContaining('/120 corretti'), findsOneWidget);
  });
}
