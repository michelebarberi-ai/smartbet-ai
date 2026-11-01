import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_holdout_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';

void main() {
  const service = SmartBetFrozenHoldoutService();

  final freeze = DateTime.utc(2026, 8, 31);
  final validationStart = DateTime.utc(2026, 9, 1);
  final asOf = DateTime.utc(2026, 10, 1);

  SmartBetAnalysisRecord record(
    int fixtureId,
    DateTime kickoff, {
    bool correct = true,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
    bool qualified = true,
    DateTime? resolvedAt,
  }) {
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Test',
      country: 'Test',
      matchDate: kickoff,
      market: market,
      probability: 0.80,
      smartScore: 80,
      confidence: null,
      classification: null,
      qualified: engine == SmartBetAnalysisEngine.diego ? qualified : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 2,
      actualAwayGoals: correct ? 1 : 0,
      firstSeenAt: kickoff.subtract(const Duration(hours: 12)),
      lastSeenAt: kickoff.add(const Duration(hours: 4)),
      resolvedAt: resolvedAt ?? kickoff.add(const Duration(hours: 4)),
    );
  }

  SmartBetShadowOutcomeCase shadow(SmartBetAnalysisRecord r) {
    return SmartBetShadowOutcomeCase(
      record: r,
      prediction: SmartBetShadowPrediction(
        key: r.key,
        engine: r.engine.name,
        market: r.market,
        fixtureId: r.fixtureId,
        predictedAt: r.firstSeenAt,
        originalProbability: r.probability!,
        calibratedProbability: r.probability!,
        trainingSampleSize: 0,
        calibrationApplied: false,
      ),
    );
  }

  List<SmartBetAnalysisRecord> training() => [
    for (var i = 0; i < 50; i++)
      record(
        i + 1000,
        DateTime.utc(2026, 8, 1, 18).add(Duration(days: i ~/ 2)),
        correct: i.isOdd,
      ),
  ];

  List<SmartBetShadowOutcomeCase> validation() => [
    for (var i = 0; i < 30; i++)
      shadow(
        record(
          i + 2000,
          DateTime.utc(2026, 9, 10, 18).add(Duration(days: i ~/ 2)),
          correct: i.isOdd,
        ),
      ),
  ];

  SmartBetFrozenHoldoutReport run({
    List<SmartBetAnalysisRecord>? history,
    List<SmartBetShadowOutcomeCase>? samples,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
  }) {
    return service.evaluate(
      records: history ?? training(),
      cases: samples ?? validation(),
      engine: engine,
      market: market,
      trainingCutoff: freeze,
      validationStartsAt: validationStart,
      asOf: asOf,
    );
  }

  test('addestramento congelato e validazione separata', () {
    final report = run();

    expect(report.trainingFixtures, 50);
    expect(report.validationFixtures, 30);
    expect(report.distinctValidationDays, 15);
    expect(report.originalBrier, closeTo(0.34, 1e-9));
    expect(report.frozenCalibratedBrier, closeTo(0.29, 1e-9));
    expect(report.brierImprovement, closeTo(0.05, 1e-9));
    expect(report.sufficientForExploratoryReview, true);
  });

  test('risultati della validazione non entrano nel training', () {
    final futureRecords = validation().map((item) => item.record).toList();

    final report = run(history: [...training(), ...futureRecords]);

    expect(report.trainingFixtures, 50);
    expect(report.brierImprovement, closeTo(0.05, 1e-9));
  });

  test('duplicati nella validazione esclusi', () {
    final samples = validation();

    final report = run(samples: [...samples, samples.first, samples.first]);

    expect(report.validationFixtures, 30);
  });

  test('risultati conosciuti dopo asOf esclusi', () {
    final late = record(
      4000,
      DateTime.utc(2026, 9, 12, 18),
      resolvedAt: DateTime.utc(2026, 10, 3),
    );

    final report = run(samples: [shadow(late)]);

    expect(report.validationFixtures, 0);
    expect(report.brierImprovement, isNull);
  });

  test('training insufficiente non produce calibrazione', () {
    final report = run(history: training().take(49).toList());

    expect(report.trainingFixtures, 49);
    expect(report.validationFixtures, 0);
    expect(report.sufficientForExploratoryReview, false);
  });

  test('non mescola mercati o motori', () {
    final report = run(engine: SmartBetAnalysisEngine.diego);

    expect(report.trainingFixtures, 0);
    expect(report.validationFixtures, 0);

    final otherMarket = run(market: 'OVER 2.5');
    expect(otherMarket.trainingFixtures, 0);
  });
}
