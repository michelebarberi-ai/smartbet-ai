import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/smartbet_analysis_history_store.dart';
import '../../lib/services/smartbet_walk_forward_backtest_service.dart';

void main() {
  const service = SmartBetWalkForwardBacktestService();

  SmartBetAnalysisRecord record({
    required int id,
    required DateTime predictedAt,
    required DateTime resolvedAt,
    required bool correct,
    double probability = 0.80,
    String market = 'GOAL',
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  }) {
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: id,
      homeTeam: 'Home',
      awayTeam: 'Away',
      league: 'Serie A',
      country: 'Italy',
      matchDate: predictedAt.add(const Duration(days: 1)),
      market: market,
      probability: probability,
      smartScore: 70,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 2,
      actualAwayGoals: 1,
      firstSeenAt: predictedAt,
      lastSeenAt: resolvedAt,
      resolvedAt: resolvedAt,
    );
  }

  List<SmartBetAnalysisRecord> history(int count) {
    return List.generate(
      count,
      (i) => record(
        id: i + 1,
        predictedAt: DateTime.utc(2026, 9, 10),
        resolvedAt: DateTime.utc(2026, 9, 12),
        correct: i < count ~/ 2,
      ),
    );
  }

  SmartBetAnalysisRecord target({bool correct = false}) {
    return record(
      id: 999,
      predictedAt: DateTime.utc(2026, 10, 20),
      resolvedAt: DateTime.utc(2026, 10, 22),
      correct: correct,
    );
  }

  test('senza 50 precedenti non applica correzioni', () {
    final report = service.evaluate([...history(49), target()]);

    final tested = report.cases.last;

    expect(tested.fixtureId, 999);
    expect(tested.trainingSampleSize, 49);
    expect(tested.adjusted, false);
    expect(report.adjustedRecords, 0);
    expect(report.brierImprovement, isNull);
  });

  test('confronta Brier originale e calibrato', () {
    final report = service.evaluate([...history(50), target()]);

    final tested = report.cases.last;

    expect(tested.trainingSampleSize, 50);
    expect(tested.originalProbability, 0.80);
    expect(tested.calibratedProbability, closeTo(0.70, 0.0001));
    expect(tested.originalBrier, closeTo(0.64, 0.0001));
    expect(tested.calibratedBrier, closeTo(0.49, 0.0001));

    expect(report.adjustedRecords, 1);
    expect(report.brierImprovement, closeTo(0.15, 0.0001));
  });

  test('la calibrazione puo anche peggiorare', () {
    final report = service.evaluate([...history(50), target(correct: true)]);

    expect(report.adjustedRecords, 1);
    expect(report.brierImprovement, closeTo(-0.05, 0.0001));
  });

  test('non usa un risultato conosciuto dopo la previsione', () {
    final records = history(49);

    records.add(
      record(
        id: 500,
        predictedAt: DateTime.utc(2026, 9, 10),
        resolvedAt: DateTime.utc(2026, 10, 23),
        correct: false,
      ),
    );

    final report = service.evaluate([...records, target()]);

    final tested = report.cases.last;

    expect(tested.trainingSampleSize, 49);
    expect(tested.adjusted, false);
  });

  test('non usa un mercato differente', () {
    final records = history(49);

    records.add(
      record(
        id: 500,
        predictedAt: DateTime.utc(2026, 9, 10),
        resolvedAt: DateTime.utc(2026, 9, 12),
        correct: false,
        market: 'OVER 2.5',
      ),
    );

    final report = service.evaluate([...records, target()]);

    expect(report.cases.last.trainingSampleSize, 49);
    expect(report.cases.last.adjusted, false);
  });
}
