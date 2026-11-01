import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_registration_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';
import 'package:smartbet_ai_new/services/smartbet_registered_frozen_audit_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';

void main() {
  const auditor = SmartBetRegisteredFrozenAuditService();

  final freeze = DateTime.utc(2026, 9, 1);
  final registrationTime = DateTime.utc(2026, 10, 1);
  final asOf = DateTime.utc(2026, 11, 1);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SmartBetFrozenModelRegistrationStore store() =>
      SmartBetFrozenModelRegistrationStore(clock: () => registrationTime);

  SmartBetAnalysisRecord record({
    required int id,
    required DateTime kickoff,
    bool correct = false,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    DateTime? predictedAt,
    DateTime? resolvedAt,
  }) {
    final predictionTime =
        predictedAt ?? kickoff.subtract(const Duration(hours: 12));
    final resultTime = resolvedAt ?? kickoff.add(const Duration(hours: 4));

    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: id,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Test',
      country: 'Test',
      matchDate: kickoff,
      market: 'GOAL',
      probability: 0.80,
      smartScore: 80,
      confidence: null,
      classification: null,
      qualified: engine == SmartBetAnalysisEngine.diego ? true : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 2,
      actualAwayGoals: correct ? 1 : 0,
      firstSeenAt: predictionTime,
      lastSeenAt: resultTime,
      resolvedAt: resultTime,
    );
  }

  SmartBetFrozenModelSnapshot model() {
    final history = [
      for (var i = 0; i < 50; i++)
        record(
          id: i + 1000,
          kickoff: DateTime.utc(2026, 8, 1, 18).add(Duration(days: i ~/ 2)),
          correct: i.isOdd,
        ),
    ];

    return SmartBetFrozenModelSnapshot.prepare(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      frozenAt: freeze,
      records: history,
    )!;
  }

  SmartBetShadowOutcomeCase sample(
    int i, {
    DateTime? predictedAt,
    DateTime? resolvedAt,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  }) {
    final kickoff = DateTime.utc(2026, 10, 5, 18).add(Duration(days: i ~/ 2));

    final r = record(
      id: i + 2000,
      kickoff: kickoff,
      correct: i.isOdd,
      engine: engine,
      predictedAt: predictedAt,
      resolvedAt: resolvedAt,
    );

    return SmartBetShadowOutcomeCase(
      record: r,
      prediction: SmartBetShadowPrediction(
        key: r.key,
        engine: engine.name,
        market: 'GOAL',
        fixtureId: r.fixtureId,
        predictedAt: r.firstSeenAt,
        originalProbability: 0.80,
        calibratedProbability: 0.80,
        trainingSampleSize: 0,
        calibrationApplied: false,
      ),
    );
  }

  List<SmartBetShadowOutcomeCase> validation() => [
    for (var i = 0; i < 30; i++) sample(i),
  ];

  test('senza registrazione nessun audit', () async {
    final result = await auditor.evaluate(
      store: store(),
      modelId: model().id,
      cases: validation(),
      asOf: asOf,
    );

    expect(result.status, SmartBetRegisteredAuditStatus.missingRegistration);
    expect(result.audit, isNull);
  });

  test('30 previsioni successive sono valutate', () async {
    final repository = store();
    final snapshot = model();
    await repository.register(snapshot);

    final result = await auditor.evaluate(
      store: repository,
      modelId: snapshot.id,
      cases: validation(),
      asOf: asOf,
    );

    expect(result.evaluated, isTrue);
    expect(result.excludedBeforeRegistration, 0);
    expect(result.audit!.validationFixtures, 30);
    expect(result.audit!.distinctDays, 15);
    expect(result.audit!.brierImprovement, closeTo(0.05, 1e-9));
  });

  test('previsione precedente alla registrazione esclusa', () async {
    final repository = store();
    final snapshot = model();
    await repository.register(snapshot);

    final result = await auditor.evaluate(
      store: repository,
      modelId: snapshot.id,
      cases: [sample(0, predictedAt: DateTime.utc(2026, 9, 30))],
      asOf: asOf,
    );

    expect(result.excludedBeforeRegistration, 1);
    expect(result.audit!.validationFixtures, 0);
  });

  test('previsione esattamente alla registrazione esclusa', () async {
    final repository = store();
    final snapshot = model();
    await repository.register(snapshot);

    final result = await auditor.evaluate(
      store: repository,
      modelId: snapshot.id,
      cases: [
        sample(0, predictedAt: registrationTime),
        sample(1),
      ],
      asOf: asOf,
    );

    expect(result.excludedBeforeRegistration, 1);
    expect(result.audit!.validationFixtures, 1);
  });

  test('riapertura dello store conserva la validazione', () async {
    final first = store();
    final snapshot = model();
    await first.register(snapshot);

    final reopened = store();

    final result = await auditor.evaluate(
      store: reopened,
      modelId: snapshot.id,
      cases: validation(),
      asOf: asOf,
    );

    expect(result.evaluated, isTrue);
    expect(result.audit!.validationFixtures, 30);
  });

  test('cutoff non successivo alla registrazione blocca', () async {
    final repository = store();
    final snapshot = model();
    await repository.register(snapshot);

    final result = await auditor.evaluate(
      store: repository,
      modelId: snapshot.id,
      cases: validation(),
      asOf: registrationTime,
    );

    expect(result.status, SmartBetRegisteredAuditStatus.invalidChronology);
    expect(result.audit, isNull);
  });

  test('motore differente viene escluso dall auditor', () async {
    final repository = store();
    final snapshot = model();
    await repository.register(snapshot);

    final result = await auditor.evaluate(
      store: repository,
      modelId: snapshot.id,
      cases: [
        sample(0),
        sample(1, engine: SmartBetAnalysisEngine.diego),
      ],
      asOf: asOf,
    );

    expect(result.audit!.validationFixtures, 1);
    expect(result.audit!.excludedCases, 1);
  });

  test('risultati futuri esclusi anche dopo registrazione', () async {
    final repository = store();
    final snapshot = model();
    await repository.register(snapshot);

    final result = await auditor.evaluate(
      store: repository,
      modelId: snapshot.id,
      cases: [sample(0, resolvedAt: DateTime.utc(2026, 11, 3))],
      asOf: asOf,
    );

    expect(result.audit!.validationFixtures, 0);
    expect(result.audit!.brierImprovement, isNull);
  });
}
