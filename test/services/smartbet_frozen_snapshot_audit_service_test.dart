import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_snapshot_audit_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';

void main() {
  const auditor = SmartBetFrozenSnapshotAuditService();

  final freeze = DateTime.utc(2026, 9, 1);
  final asOf = DateTime.utc(2026, 11, 1);

  SmartBetAnalysisRecord record({
    required int id,
    required DateTime kickoff,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
    bool correct = false,
    bool qualified = true,
    DateTime? predictedAt,
    DateTime? resolvedAt,
  }) {
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: id,
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
      firstSeenAt: predictedAt ?? kickoff.subtract(const Duration(hours: 12)),
      lastSeenAt: resolvedAt ?? kickoff.add(const Duration(hours: 4)),
      resolvedAt: resolvedAt ?? kickoff.add(const Duration(hours: 4)),
    );
  }

  SmartBetFrozenModelSnapshot model({
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  }) {
    final training = [
      for (var i = 0; i < 50; i++)
        record(
          id: i + 1000,
          kickoff: DateTime.utc(2026, 8, 1, 18).add(Duration(days: i ~/ 2)),
          engine: engine,
          correct: i.isOdd,
        ),
    ];

    return SmartBetFrozenModelSnapshot.prepare(
      engine: engine,
      market: 'GOAL',
      frozenAt: freeze,
      records: training,
    )!;
  }

  SmartBetShadowOutcomeCase sample(
    int i, {
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
    bool? correct,
    bool qualified = true,
    DateTime? predictedAt,
    DateTime? resolvedAt,
    double storedCalibrated = 0.80,
  }) {
    final kickoff = DateTime.utc(2026, 10, 1, 18).add(Duration(days: i ~/ 2));

    final r = record(
      id: i + 2000,
      kickoff: kickoff,
      engine: engine,
      market: market,
      correct: correct ?? i.isOdd,
      qualified: qualified,
      predictedAt: predictedAt,
      resolvedAt: resolvedAt,
    );

    final snapshot = SmartBetShadowPrediction(
      key: r.key,
      engine: engine.name,
      market: market,
      fixtureId: r.fixtureId,
      predictedAt: r.firstSeenAt,
      originalProbability: 0.80,
      calibratedProbability: storedCalibrated,
      trainingSampleSize: 0,
      calibrationApplied: false,
    );

    return SmartBetShadowOutcomeCase(record: r, prediction: snapshot);
  }

  List<SmartBetShadowOutcomeCase> validation() => [
    for (var i = 0; i < 30; i++) sample(i),
  ];

  test('modello congelato valuta 30 fixture successive', () {
    final frozen = model();

    final report = auditor.evaluate(
      model: frozen,
      cases: validation(),
      asOf: asOf,
    );

    expect(report.modelId, frozen.id);
    expect(report.validationFixtures, 30);
    expect(report.distinctDays, 15);
    expect(report.originalBrier, closeTo(0.34, 1e-9));
    expect(report.frozenBrier, closeTo(0.29, 1e-9));
    expect(report.brierImprovement, closeTo(0.05, 1e-9));
    expect(report.enoughForExploratoryReview, true);
  });

  test('duplicati non aumentano il numero di fixture', () {
    final items = validation();

    final report = auditor.evaluate(
      model: model(),
      cases: [...items, items.first],
      asOf: asOf,
    );

    expect(report.validationFixtures, 30);
    expect(report.excludedCases, 1);
  });

  test('risultati successivi al cutoff sono esclusi', () {
    final report = auditor.evaluate(
      model: model(),
      cases: [sample(0, resolvedAt: DateTime.utc(2026, 11, 3))],
      asOf: asOf,
    );

    expect(report.validationFixtures, 0);
    expect(report.brierImprovement, isNull);
  });

  test('previsioni precedenti al congelamento escluse', () {
    final report = auditor.evaluate(
      model: model(),
      cases: [sample(0, predictedAt: DateTime.utc(2026, 8, 30))],
      asOf: asOf,
    );

    expect(report.validationFixtures, 0);
  });

  test('motori e mercati differenti non si mescolano', () {
    final report = auditor.evaluate(
      model: model(),
      cases: [
        sample(0),
        sample(1, engine: SmartBetAnalysisEngine.diego),
        sample(2, market: 'OVER 2.5'),
      ],
      asOf: asOf,
    );

    expect(report.validationFixtures, 1);
    expect(report.excludedCases, 2);
  });

  test('Diego non qualificato escluso', () {
    final report = auditor.evaluate(
      model: model(engine: SmartBetAnalysisEngine.diego),
      cases: [
        sample(0, engine: SmartBetAnalysisEngine.diego, qualified: false),
      ],
      asOf: asOf,
    );

    expect(report.validationFixtures, 0);
  });

  test('non usa la vecchia calibrazione dello snapshot', () {
    final report = auditor.evaluate(
      model: model(),
      cases: [
        sample(0, storedCalibrated: 0.99),
        sample(1, storedCalibrated: 0.99),
      ],
      asOf: asOf,
    );

    // Usa il modello congelato: 0.8 -> 0.7.
    // Un errore e un successo producono Brier medio 0.29.
    expect(report.frozenBrier, closeTo(0.29, 1e-9));
  });

  test('un modello che peggiora resta riconoscibile', () {
    final report = auditor.evaluate(
      model: model(),
      cases: [for (var i = 0; i < 30; i++) sample(i, correct: true)],
      asOf: asOf,
    );

    expect(report.validationFixtures, 30);
    expect(report.brierImprovement, lessThan(0));
    expect(report.earlyImprovement, lessThan(0));
    expect(report.recentImprovement, lessThan(0));
  });
}
