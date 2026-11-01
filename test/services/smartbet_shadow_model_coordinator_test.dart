import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_registration_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_model_coordinator.dart';

void main() {
  const coordinator = SmartBetShadowModelCoordinator();
  final now = DateTime.utc(2026, 11, 1, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SmartBetAnalysisRecord record(
    int index, {
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
    DateTime? resolvedAt,
  }) {
    final kickoff = DateTime.utc(
      2026,
      8,
      1,
      18,
    ).add(Duration(days: index ~/ 2));

    final resolved = resolvedAt ?? kickoff.add(const Duration(hours: 4));

    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: index + 1000,
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
      qualified: engine == SmartBetAnalysisEngine.diego ? true : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: index.isOdd
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 2,
      actualAwayGoals: index.isOdd ? 1 : 0,
      firstSeenAt: kickoff.subtract(const Duration(hours: 12)),
      lastSeenAt: resolved,
      resolvedAt: resolved,
    );
  }

  List<SmartBetAnalysisRecord> history({
    int count = 50,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
  }) => [
    for (var i = 0; i < count; i++) record(i, engine: engine, market: market),
  ];

  SmartBetFrozenModelRegistrationStore registry() =>
      SmartBetFrozenModelRegistrationStore(clock: () => now);

  Future<SmartBetShadowModelPreparationReport> run(
    List<SmartBetAnalysisRecord> records,
    SmartBetFrozenModelSnapshotStore models,
    SmartBetFrozenModelRegistrationStore registrations,
  ) {
    return coordinator.prepare(
      history: records,
      asOf: now,
      modelStore: models,
      registrationStore: registrations,
    );
  }

  test('49 partite non producono un modello', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registrations = registry();

    final report = await run(history(count: 49), models, registrations);

    expect(report.createdModels, 0);
    expect(registrations.registrations, isEmpty);
    expect(models.snapshots, isEmpty);
  });

  test('50 partite registrano il primo modello', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registrations = registry();

    final report = await run(history(), models, registrations);

    expect(report.successful, isTrue);
    expect(report.eligibleMarkets, 1);
    expect(report.createdModels, 1);
    expect(models.snapshots.length, 1);
    expect(registrations.registrations.length, 1);
    expect(registrations.registrations.single.registeredAt, now);
  });

  test('riesecuzione non cambia il modello', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registrations = registry();

    await run(history(), models, registrations);

    final original = registrations.registrations.single.model.id;

    final second = await run(history(), models, registrations);

    expect(second.createdModels, 0);
    expect(second.existingModels, 1);
    expect(registrations.registrations.length, 1);
    expect(registrations.registrations.single.model.id, original);
  });

  test('motori diversi mantengono modelli separati', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registrations = registry();

    final report = await run(
      [...history(), ...history(engine: SmartBetAnalysisEngine.diego)],
      models,
      registrations,
    );

    expect(report.createdModels, 2);
    expect(registrations.registrations.length, 2);
    expect(report.successful, isTrue);
  });

  test('mercati diversi non condividono correzioni', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registrations = registry();

    final report = await run(
      [...history(), ...history(market: 'OVER 2.5')],
      models,
      registrations,
    );

    expect(report.createdModels, 2);
    expect(registrations.registrations.length, 2);
  });

  test('risultati successivi al cutoff non entrano', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registrations = registry();

    final records = history(count: 49)
      ..add(record(49, resolvedAt: DateTime.utc(2026, 11, 1, 1)));

    final report = await run(records, models, registrations);

    expect(report.createdModels, 0);
    expect(registrations.registrations, isEmpty);
  });
}
