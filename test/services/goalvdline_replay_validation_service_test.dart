import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_replay_validation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_store.dart';

void main() {
  const validator = GoalVdLineReplayValidationService();
  final kickoff = DateTime.utc(2026, 11, 11, 18);
  final asOf = DateTime.utc(2026, 11, 15, 18);

  SmartBetSimulationShadowSnapshot snapshot({
    int fixtureId = 12,
    double quality = 0.8,
    DateTime? matchDate,
    DateTime? capturedAt,
    String engine = 'SMARTBET',
  }) {
    final date = matchDate ?? kickoff;
    return SmartBetSimulationShadowSnapshot(
      fixtureId: fixtureId,
      engine: engine,
      matchDate: date,
      capturedAt: capturedAt ?? date.subtract(const Duration(hours: 2)),
      modelVersion: 'p21a-bivariate-poisson-v1',
      expectedHomeGoals: 1.45,
      expectedAwayGoals: 1.05,
      dataQuality: quality,
      originalProbabilities: const {
        '1': 0.49, 'X': 0.27, '2': 0.24,
        'GOAL': 0.54, 'OVER 2.5': 0.47,
      },
      simulatedProbabilities: const {
        '1': 0.44, 'X': 0.27, '2': 0.29,
        'GOAL': 0.51, 'OVER 2.5': 0.46,
      },
      unsupportedMarkets: const [],
    );
  }

  SmartBetAnalysisRecord record({
    int fixtureId = 12,
    int home = 2,
    int away = 1,
    DateTime? matchDate,
    DateTime? firstSeenAt,
    DateTime? resolvedAt,
    bool prospective = true,
    String market = '1',
  }) {
    final date = matchDate ?? kickoff;
    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: fixtureId,
      homeTeam: 'Casa',
      awayTeam: 'Trasferta',
      country: 'Italia',
      league: 'Serie A',
      matchDate: date,
      market: market,
      probability: 0.49,
      smartScore: 65,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: home > away
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: home,
      actualAwayGoals: away,
      firstSeenAt: firstSeenAt ?? date.subtract(const Duration(hours: 2)),
      lastSeenAt: date.add(const Duration(hours: 8)),
      resolvedAt: resolvedAt ?? date.add(const Duration(hours: 8)),
    );
  }

  test('B54: senza dati veri non dichiara miglioramenti o campioni', () {
    final report = validator.evaluate(
      snapshots: [],
      history: [],
      asOf: asOf,
    );
    expect(report.sourceSnapshots, 0);
    expect(report.eligibleSnapshots, 0);
    expect(report.metrics, isEmpty);
    expect(report.exploratorySignals, 0);
    expect(report.changesOfficialPredictions, isFalse);
  });

  test('B54: confronta solo punteggi finali prepartita realmente risolti', () {
    final report = validator.evaluate(
      snapshots: [snapshot()],
      history: [record()],
      asOf: asOf,
    );
    expect(report.sourceSnapshots, 1);
    expect(report.eligibleSnapshots, 1);
    expect(report.pendingResults, 0);
    final win = report.metrics.singleWhere((m) => m.market == '1');
    expect(win.fixtures, 1);
    expect(win.engine, 'SMARTBET');
    expect(win.originalBrier, closeTo((1 - .49) * (1 - .49), 1e-12));
    expect(win.priorSimulatorBrier, closeTo((1 - .44) * (1 - .44), 1e-12));
    expect(win.minuteReplayBrier, inInclusiveRange(0, 1));
    expect(win.enoughObservations, isFalse);
    expect(win.exploratoryPositive, isFalse);
    expect(report.changesOfficialPredictions, isFalse);
  });

  test('B54: niente accesso a risultati futuri, non-prospettici o risolti dopo cutoff', () {
    final report = validator.evaluate(
      snapshots: [
        snapshot(fixtureId: 1),
        snapshot(fixtureId: 2),
        snapshot(fixtureId: 3),
      ],
      history: [
        record(fixtureId: 1, resolvedAt: asOf.add(const Duration(days: 1))),
        record(fixtureId: 2, prospective: false),
        record(fixtureId: 3, firstSeenAt: kickoff.add(const Duration(minutes: 1))),
      ],
      asOf: asOf,
    );
    expect(report.pendingResults, 3);
    expect(report.eligibleSnapshots, 0);
    expect(report.metrics, isEmpty);
  });

  test('B54: blocca fixture con risultati contraddittori e snapshot duplicati', () {
    final report = validator.evaluate(
      snapshots: [
        snapshot(fixtureId: 8),
        snapshot(fixtureId: 8),
      ],
      history: [
        record(fixtureId: 8, home: 2, away: 1, market: '1'),
        record(fixtureId: 8, home: 0, away: 2, market: '2'),
      ],
      asOf: asOf,
    );
    expect(report.contradictoryResults, 1);
    expect(report.duplicateSnapshots, 1);
    expect(report.eligibleSnapshots, 0);
  });

  test('B54: distingue qualità debole da storico assente', () {
    final report = validator.evaluate(
      snapshots: [snapshot(quality: 0.48)],
      history: [record()],
      asOf: asOf,
    );
    expect(report.insufficientQuality, 1);
    expect(report.pendingResults, 0);
    expect(report.eligibleSnapshots, 0);
  });

  test('B54: un apparente vantaggio non autorizza cambiamenti ufficiali', () {
    const metric = GoalVdLineReplayValidationMetric(
      engine: 'SMARTBET',
      market: '1',
      fixtures: 105,
      matchDays: 21,
      originalBrier: 0.25,
      priorSimulatorBrier: 0.24,
      minuteReplayBrier: 0.23,
      firstHalfDifference: 0.01,
      secondHalfDifference: 0.01,
    );
    expect(metric.enoughObservations, isTrue);
    expect(metric.exploratoryPositive, isTrue);
    const report = GoalVdLineReplayValidationReport(
      sourceSnapshots: 105,
      eligibleSnapshots: 105,
      pendingResults: 0,
      duplicateSnapshots: 0,
      contradictoryResults: 0,
      invalidSnapshots: 0,
      insufficientQuality: 0,
      unmatchedMarkets: 0,
      metrics: [metric],
    );
    expect(report.changesOfficialPredictions, isFalse);
  });
}
