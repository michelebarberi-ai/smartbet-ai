import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_registration_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';
import 'package:smartbet_ai_new/services/smartbet_prospective_model_audit_service.dart';
import 'package:smartbet_ai_new/services/smartbet_registered_frozen_audit_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';

void main() {
  const auditor = SmartBetProspectiveModelAuditService();

  final freeze = DateTime.utc(2026, 9, 1);
  final registeredAt = DateTime.utc(2026, 10, 1);
  final asOf = DateTime.utc(2026, 11, 1);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SmartBetAnalysisRecord record({
    required int fixtureId,
    required DateTime kickoff,
    bool correct = false,
    DateTime? resolvedAt,
  }) {
    final resultTime = resolvedAt ?? kickoff.add(const Duration(hours: 4));

    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: fixtureId,
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
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 2,
      actualAwayGoals: correct ? 1 : 0,
      firstSeenAt: kickoff.subtract(const Duration(hours: 12)),
      lastSeenAt: resultTime,
      resolvedAt: resultTime,
    );
  }

  SmartBetFrozenModelSnapshot model() {
    final history = [
      for (var i = 0; i < 50; i++)
        record(
          fixtureId: i + 1000,
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

  SmartBetFrozenModelRegistrationStore repository() =>
      SmartBetFrozenModelRegistrationStore(clock: () => registeredAt);

  SmartBetShadowOutcomeCase sample(
    int index, {
    String? modelId,
    bool bind = true,
    DateTime? linkTime,
    DateTime? resolvedAt,
  }) {
    final kickoff = DateTime.utc(
      2026,
      10,
      5,
      18,
    ).add(Duration(days: index ~/ 2));

    final r = record(
      fixtureId: index + 2000,
      kickoff: kickoff,
      correct: index.isOdd,
      resolvedAt: resolvedAt,
    );

    return SmartBetShadowOutcomeCase(
      record: r,
      prediction: SmartBetShadowPrediction(
        key: r.key,
        engine: r.engine.name,
        market: r.market,
        fixtureId: r.fixtureId,
        predictedAt: r.firstSeenAt,
        originalProbability: 0.80,
        calibratedProbability: 0.80,
        trainingSampleSize: 0,
        calibrationApplied: false,
        shadowModelId: bind ? modelId : null,
        shadowModelLinkedAt: bind
            ? (linkTime ?? r.firstSeenAt.add(const Duration(minutes: 1)))
            : null,
      ),
    );
  }

  test('30 previsioni associate sono valutate', () async {
    final store = repository();
    final snapshot = model();
    await store.register(snapshot);

    final result = await auditor.evaluate(
      store: store,
      modelId: snapshot.id,
      cases: [for (var i = 0; i < 30; i++) sample(i, modelId: snapshot.id)],
      asOf: asOf,
    );

    expect(result.validatedFixtures, 30);
    expect(result.excludedWithoutModel, 0);
    expect(result.brierImprovement, closeTo(0.05, 1e-9));
    expect(result.exploratoryEvidenceAvailable, isTrue);
  });

  test('snapshot legacy senza modello escluso', () async {
    final store = repository();
    final snapshot = model();
    await store.register(snapshot);

    final result = await auditor.evaluate(
      store: store,
      modelId: snapshot.id,
      cases: [sample(0, bind: false)],
      asOf: asOf,
    );

    expect(result.excludedWithoutModel, 1);
    expect(result.validatedFixtures, 0);
  });

  test('associazione a un altro modello esclusa', () async {
    final store = repository();
    final snapshot = model();
    await store.register(snapshot);

    final result = await auditor.evaluate(
      store: store,
      modelId: snapshot.id,
      cases: [sample(0, modelId: 'modello-diverso')],
      asOf: asOf,
    );

    expect(result.excludedWrongModel, 1);
    expect(result.validatedFixtures, 0);
  });

  test('orari incoerenti non sono accettati', () async {
    final store = repository();
    final snapshot = model();
    await store.register(snapshot);

    final result = await auditor.evaluate(
      store: store,
      modelId: snapshot.id,
      cases: [
        sample(0, modelId: snapshot.id, linkTime: DateTime.utc(2026, 9, 30)),
        sample(1, modelId: snapshot.id, linkTime: DateTime.utc(2026, 10, 20)),
      ],
      asOf: asOf,
    );

    expect(result.excludedInvalidBinding, 2);
    expect(result.validatedFixtures, 0);
  });

  test('duplicati non aumentano le partite valide', () async {
    final store = repository();
    final snapshot = model();
    await store.register(snapshot);

    final first = sample(0, modelId: snapshot.id);

    final result = await auditor.evaluate(
      store: store,
      modelId: snapshot.id,
      cases: [first, first],
      asOf: asOf,
    );

    expect(result.validatedFixtures, 1);
    expect(result.registeredAudit.audit!.excludedCases, 1);
  });

  test('nessuna registrazione significa nessun audit', () async {
    final snapshot = model();

    final result = await auditor.evaluate(
      store: repository(),
      modelId: snapshot.id,
      cases: [sample(0, modelId: snapshot.id)],
      asOf: asOf,
    );

    expect(
      result.registeredAudit.status,
      SmartBetRegisteredAuditStatus.missingRegistration,
    );
    expect(result.validatedFixtures, 0);
  });

  test('risultati successivi al cutoff esclusi', () async {
    final store = repository();
    final snapshot = model();
    await store.register(snapshot);

    final result = await auditor.evaluate(
      store: store,
      modelId: snapshot.id,
      cases: [
        sample(0, modelId: snapshot.id, resolvedAt: DateTime.utc(2026, 11, 3)),
      ],
      asOf: asOf,
    );

    expect(result.validatedFixtures, 0);
    expect(result.brierImprovement, isNull);
  });
}
