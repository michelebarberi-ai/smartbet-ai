import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';

void main() {
  const service = SmartBetShadowOutcomeService();

  final predictedAt = DateTime.utc(2026, 10, 20);
  final matchDate = DateTime.utc(2026, 10, 21);
  final resolvedAt = DateTime.utc(2026, 10, 22);

  SmartBetAnalysisRecord record({
    int id = 1,
    bool correct = false,
    bool pending = false,
    bool legacy = false,
    double probability = 0.80,
  }) {
    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: id,
      homeTeam: 'Home',
      awayTeam: 'Away',
      league: 'Serie A',
      country: 'Italy',
      matchDate: matchDate,
      market: 'GOAL',
      probability: probability,
      smartScore: 70,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: pending
          ? SmartBetAnalysisStatus.pending
          : correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: pending ? null : 2,
      actualAwayGoals: pending ? null : 1,
      firstSeenAt: predictedAt,
      lastSeenAt: resolvedAt,
      resolvedAt: legacy || pending ? null : resolvedAt,
    );
  }

  SmartBetShadowPrediction snapshot({
    int id = 1,
    double original = 0.80,
    double calibrated = 0.70,
    DateTime? capturedAt,
  }) {
    return SmartBetShadowPrediction(
      key: 'smartBet|$id|GOAL',
      engine: 'smartBet',
      market: 'GOAL',
      fixtureId: id,
      predictedAt: capturedAt ?? predictedAt,
      originalProbability: original,
      calibratedProbability: calibrated,
      trainingSampleSize: 50,
      calibrationApplied: true,
    );
  }

  test('riconosce quando la calibrazione migliora', () {
    final report = service.evaluate(
      history: [record()],
      predictions: [snapshot()],
    );

    expect(report.overall.evaluated, 1);
    expect(report.overall.adjusted, 1);
    expect(report.overall.improved, 1);
    expect(report.overall.worsened, 0);
    expect(report.overall.originalBrier, closeTo(0.64, 0.0001));
    expect(report.overall.calibratedBrier, closeTo(0.49, 0.0001));
    expect(report.overall.improvement, closeTo(0.15, 0.0001));
  });

  test('riconosce quando la calibrazione peggiora', () {
    final report = service.evaluate(
      history: [record(correct: true)],
      predictions: [snapshot()],
    );

    expect(report.overall.evaluated, 1);
    expect(report.overall.improved, 0);
    expect(report.overall.worsened, 1);
    expect(report.overall.improvement, closeTo(-0.05, 0.0001));
  });

  test('ignora risultati pendenti e legacy', () {
    final report = service.evaluate(
      history: [record(id: 1, pending: true), record(id: 2, legacy: true)],
      predictions: [snapshot(id: 1), snapshot(id: 2)],
    );

    expect(report.overall.evaluated, 0);
    expect(report.overall.improvement, isNull);
  });

  test('non abbina snapshot con data o probabilita diversa', () {
    final report = service.evaluate(
      history: [record(id: 1), record(id: 2)],
      predictions: [
        snapshot(id: 1, capturedAt: DateTime.utc(2026, 10, 19)),
        snapshot(id: 2, original: 0.60),
      ],
    );

    expect(report.overall.evaluated, 0);
  });
}
