import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_scorer_learning_service.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_public_learning_card.dart';

void main() {
  final kickoff = DateTime.utc(2026, 11, 20, 20);
  final cutoff = DateTime.utc(2026, 11, 22, 20);

  SmartBetAnalysisRecord record({
    required int fixtureId,
    required SmartBetAnalysisEngine engine,
    required SmartBetAnalysisStatus status,
    bool prospective = true,
    DateTime? outcomeKnownBy,
  }) => SmartBetAnalysisRecord(
    engine: engine,
    fixtureId: fixtureId,
    homeTeam: 'Casa',
    awayTeam: 'Ospiti',
    league: 'Serie A',
    country: 'Italia',
    matchDate: kickoff,
    market: '1',
    probability: 0.67,
    smartScore: engine == SmartBetAnalysisEngine.smartBet ? 75 : null,
    confidence: engine == SmartBetAnalysisEngine.diego ? 75 : null,
    classification: null,
    qualified: null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: prospective,
    status: status,
    actualHomeGoals: 2,
    actualAwayGoals: 0,
    firstSeenAt: kickoff.subtract(const Duration(hours: 2)),
    lastSeenAt: kickoff,
    resolvedAt: outcomeKnownBy ?? kickoff.add(const Duration(hours: 4)),
  );

  SmartBetScorerLearningRecord scorer({
    required int playerId,
    required int goals,
    DateTime? resolvedAt,
  }) => SmartBetScorerLearningRecord(
    fixtureId: 200,
    playerId: playerId,
    playerName: 'Giocatore',
    kickoffAt: kickoff,
    predictedAt: kickoff.subtract(const Duration(hours: 2)),
    originalProbability: 0.42,
    actualGoals: goals,
    resolvedAt: resolvedAt ?? kickoff.add(const Duration(hours: 4)),
  );

  test('B63: separate rates use only verified prospective records', () {
    final summary = GoalVdLinePublicLearningSummary.fromRecords([
      record(fixtureId: 1, engine: SmartBetAnalysisEngine.smartBet,
        status: SmartBetAnalysisStatus.correct),
      record(fixtureId: 1, engine: SmartBetAnalysisEngine.smartBet,
        status: SmartBetAnalysisStatus.correct), // duplicate
      record(fixtureId: 2, engine: SmartBetAnalysisEngine.smartBet,
        status: SmartBetAnalysisStatus.wrong),
      record(fixtureId: 3, engine: SmartBetAnalysisEngine.diego,
        status: SmartBetAnalysisStatus.correct),
      record(fixtureId: 4, engine: SmartBetAnalysisEngine.diego,
        status: SmartBetAnalysisStatus.correct, prospective: false),
      record(fixtureId: 5, engine: SmartBetAnalysisEngine.smartBet,
        status: SmartBetAnalysisStatus.correct,
        outcomeKnownBy: cutoff.add(const Duration(days: 1))),
    ], scorerRecords: [
      scorer(playerId: 11, goals: 1),
      scorer(playerId: 11, goals: 1), // duplicate
      scorer(playerId: 12, goals: 0),
      scorer(playerId: 13, goals: 1,
        resolvedAt: cutoff.add(const Duration(days: 1))),
    ], asOf: cutoff);

    expect(summary.verifiedPredictions, 3);
    expect(summary.smartBetVerified, 2);
    expect(summary.smartBetCorrect, 1);
    expect(summary.diegoVerified, 1);
    expect(summary.diegoCorrect, 1);
    expect(summary.scorerVerified, 2);
    expect(summary.scorerScored, 1);
  });

  testWidgets('B63: Home displays three compact independently sourced rates',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLinePublicLearningCard(
            records: [
              record(fixtureId: 1, engine: SmartBetAnalysisEngine.smartBet,
                status: SmartBetAnalysisStatus.correct),
              record(fixtureId: 2, engine: SmartBetAnalysisEngine.smartBet,
                status: SmartBetAnalysisStatus.wrong),
              record(fixtureId: 3, engine: SmartBetAnalysisEngine.diego,
                status: SmartBetAnalysisStatus.correct),
            ],
            scorerRecords: [
              scorer(playerId: 11, goals: 1),
              scorer(playerId: 12, goals: 0),
            ],
            asOf: cutoff,
          ),
        ),
      ),
    ));
    expect(find.byKey(const Key('b63-home-three-engine-accuracy')),
      findsOneWidget);
    expect(find.text('SmartBet'), findsOneWidget);
    expect(find.text('Diego'), findsOneWidget);
    expect(find.text('Marcatori'), findsOneWidget);
    expect(find.text('50.0%'), findsNWidgets(2));
    expect(find.text('100.0%'), findsOneWidget);
  });
}
