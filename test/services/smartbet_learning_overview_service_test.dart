import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_learning_overview_service.dart';
import 'package:smartbet_ai_new/services/smartbet_scorer_learning_service.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 12);

  SmartBetAnalysisRecord market({
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    SmartBetAnalysisStatus status = SmartBetAnalysisStatus.pending,
    bool prospective = true,
  }) {
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: 101,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Lega',
      country: 'Italia',
      matchDate: now,
      market: 'Over 2.5',
      probability: 0.65,
      smartScore: 70,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: status,
      actualHomeGoals: status == SmartBetAnalysisStatus.pending ? null : 2,
      actualAwayGoals: status == SmartBetAnalysisStatus.pending ? null : 1,
      firstSeenAt: now.subtract(const Duration(days: 2)),
      lastSeenAt: now.subtract(const Duration(days: 2)),
    );
  }

  SmartBetScorerLearningRecord scorer({
    required int fixtureId,
    required int playerId,
    bool resolved = true,
    int goals = 0,
    int daysAgo = 2,
  }) => SmartBetScorerLearningRecord(
    fixtureId: fixtureId,
    playerId: playerId,
    playerName: 'Giocatore $playerId',
    kickoffAt: now.subtract(Duration(days: daysAgo)),
    predictedAt: now.subtract(Duration(days: daysAgo + 1)),
    originalProbability: 0.35,
    actualGoals: resolved ? goals : null,
    resolvedAt: resolved ? now : null,
  );

  test('archivio vuoto non produce percentuali inventate', () {
    final s = SmartBetLearningOverview.fromRecords(
      marketRecords: const [],
      scorerRecords: const [],
    );
    expect(s.marketHitRate, isNull);
    expect(s.scorerHitRate, isNull);
    expect(s.scorerVerifiedFixtures, 0);
  });

  test('conta solo SmartBet prospettici risolti per accuratezza', () {
    final s = SmartBetLearningOverview.fromRecords(
      marketRecords: [
        market(status: SmartBetAnalysisStatus.correct),
        market(status: SmartBetAnalysisStatus.wrong),
        market(status: SmartBetAnalysisStatus.correct, prospective: false),
        market(status: SmartBetAnalysisStatus.pending),
        market(
          engine: SmartBetAnalysisEngine.diego,
          status: SmartBetAnalysisStatus.correct,
        ),
      ],
      scorerRecords: const [],
    );
    expect(s.marketRecorded, 4);
    expect(s.marketVerified, 2);
    expect(s.marketCorrect, 1);
    expect(s.marketWrong, 1);
    expect(s.marketHitRate, 50.0);
  });

  test('marcatori conta giocatori e partite distinte separatamente', () {
    final s = SmartBetLearningOverview.fromRecords(
      marketRecords: const [],
      scorerRecords: [
        scorer(fixtureId: 11, playerId: 1, goals: 1),
        scorer(fixtureId: 11, playerId: 2, goals: 0),
        scorer(fixtureId: 12, playerId: 3, resolved: false),
      ],
    );
    expect(s.scorerRecorded, 3);
    expect(s.scorerVerified, 2);
    expect(s.scorerScored, 1);
    expect(s.scorerVerifiedFixtures, 1);
    expect(s.scorerHitRate, 50.0);
  });
}
