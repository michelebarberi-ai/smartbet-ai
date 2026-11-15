import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_ui_edition.dart';
import 'package:smartbet_ai_new/services/goalvdline_external_consensus_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_public_learning_card.dart';

void main() {
  final kickoff = DateTime.utc(2026, 11, 20, 20);
  final cutoff = DateTime.utc(2026, 11, 22, 20);

  SmartBetAnalysisRecord record({
    int fixtureId = 41,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
    bool prospective = true,
    DateTime? firstSeenAt,
    DateTime? resolvedAt,
    DateTime? date,
  }) {
    final start = date ?? kickoff;
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId,
      homeTeam: 'Casa',
      awayTeam: 'Trasferta',
      league: 'Serie A',
      country: 'Italia',
      matchDate: start,
      market: '1',
      probability: 0.66,
      smartScore: 70,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: status,
      actualHomeGoals: 2,
      actualAwayGoals: 0,
      firstSeenAt: firstSeenAt ?? start.subtract(const Duration(hours: 3)),
      lastSeenAt: start,
      resolvedAt: resolvedAt ?? start.add(const Duration(hours: 4)),
    );
  }

  test('B57: public build hides diagnostic edition by default', () {
    expect(GoalVdLineUiEdition.internalDiagnostics, isFalse);
  });

  test('B57: public summary excludes retro copies and de-duplicates a fixture', () {
    final result = GoalVdLinePublicLearningSummary.fromRecords([
      record(),
      record(),
      record(fixtureId: 42, prospective: false),
      record(fixtureId: 43, firstSeenAt: kickoff.add(const Duration(minutes: 1))),
      record(fixtureId: 44, engine: SmartBetAnalysisEngine.diego),
      record(fixtureId: 45, status: SmartBetAnalysisStatus.pending),
      record(fixtureId: 46, resolvedAt: cutoff.add(const Duration(days: 1))),
    ], asOf: cutoff);
    expect(result.verifiedPredictions, 2);
    expect(result.distinctFixtures, 2);
    expect(result.smartBetVerified, 1);
    expect(result.diegoVerified, 1);
    expect(result.pendingPredictions, 0);
  });

  testWidgets('B57: public card contains no admin token or raw SHADOW controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GoalVdLinePublicLearningCard(
        records: [record()],
      )),
    ));
    expect(find.textContaining('1 partite concluse'), findsOneWidget);
    expect(find.textContaining('Token mobile'), findsNothing);
    expect(find.textContaining('LEARNING MONITOR'), findsNothing);
    expect(find.textContaining('Trasferisci storico'), findsNothing);
  });

  GoalVdLineExternalOpinion opinion({
    String source = 'publisher-a',
    int fixtureId = 91,
    String family = '1X2',
    String outcome = '1',
    DateTime? published,
    DateTime? observed,
  }) => GoalVdLineExternalOpinion(
    sourceId: source,
    fixtureId: fixtureId,
    marketFamily: family,
    outcome: outcome,
    kickoffAt: kickoff,
    publishedAt: published ?? kickoff.subtract(const Duration(hours: 6)),
    firstObservedAt: observed ?? kickoff.subtract(const Duration(hours: 5)),
    sourceReference: 'https://publisher.example/post/123',
  );

  test('B57: 3 distinct authorized publishers yield consensus, not win chance', () {
    const svc = GoalVdLineExternalConsensusService();
    final result = svc.aggregate(
      observations: [
        opinion(source: 'a'),
        opinion(source: 'b'),
        opinion(source: 'c', outcome: 'X'),
        opinion(source: 'a'),
      ],
      asOf: cutoff,
      authorizedSourceIds: {'a','b','c'},
    );
    expect(result.length, 1);
    expect(result.single.independentSources, 3);
    expect(result.single.majorityOutcome, '1');
    expect(result.single.agreementPercent, closeTo(66.666667, 1e-4));
  });

  test('B57: sources without permission and late predictions do not vote', () {
    const svc = GoalVdLineExternalConsensusService();
    final result = svc.aggregate(
      observations: [
        opinion(source:'a'),
        opinion(source:'b'),
        opinion(source:'unlicensed'),
        opinion(source:'c', published:kickoff.add(const Duration(minutes:1)),
          observed:kickoff.add(const Duration(minutes:2))),
      ],
      asOf: cutoff,
      authorizedSourceIds: {'a','b','c'},
    );
    expect(result.single.independentSources, 2);
    expect(result.single.majorityOutcome, isNull);
    expect(result.single.agreementPercent, isNull);
    expect(result.single.sufficientCoverage, isFalse);
  });

  test('B57: contradictory claims from same publisher are excluded', () {
    const svc = GoalVdLineExternalConsensusService();
    final result = svc.aggregate(
      observations: [
        opinion(source:'a', outcome:'1'),
        opinion(source:'a', outcome:'2'),
        opinion(source:'b', outcome:'1'),
        opinion(source:'c', outcome:'1'),
      ],
      asOf: cutoff,
      authorizedSourceIds: {'a','b','c'},
    );
    expect(result.single.independentSources, 2);
    expect(result.single.conflictingSources, 1);
    expect(result.single.sufficientCoverage, isFalse);
  });
}
