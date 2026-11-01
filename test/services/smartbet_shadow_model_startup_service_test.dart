import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_registration_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_model_startup_service.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  List<SmartBetAnalysisRecord> history(int count) {
    return [
      for (var i = 0; i < count; i++)
        (() {
          final kickoff = DateTime.utc(
            2026,
            8,
            1,
            18,
          ).add(Duration(days: i ~/ 2));
          final resolved = kickoff.add(const Duration(hours: 4));

          return SmartBetAnalysisRecord(
            engine: SmartBetAnalysisEngine.smartBet,
            fixtureId: i + 1000,
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
            status: i.isOdd
                ? SmartBetAnalysisStatus.correct
                : SmartBetAnalysisStatus.wrong,
            actualHomeGoals: 2,
            actualAwayGoals: i.isOdd ? 1 : 0,
            firstSeenAt: kickoff.subtract(const Duration(hours: 12)),
            lastSeenAt: resolved,
            resolvedAt: resolved,
          );
        })(),
    ];
  }

  test('49 risultati non registrano un modello', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registry = SmartBetFrozenModelRegistrationStore(clock: () => now);

    final startup = SmartBetShadowModelStartupService(
      loadHistory: () async => history(49),
      clock: () => now,
      modelStore: models,
      registrationStore: registry,
    );

    final report = await startup.run();

    expect(report, isNotNull);
    expect(report!.createdModels, 0);
    expect(models.snapshots, isEmpty);
    expect(registry.registrations, isEmpty);
  });

  test('50 risultati registrano un modello shadow', () async {
    final models = SmartBetFrozenModelSnapshotStore();
    final registry = SmartBetFrozenModelRegistrationStore(clock: () => now);

    final startup = SmartBetShadowModelStartupService(
      loadHistory: () async => history(50),
      clock: () => now,
      modelStore: models,
      registrationStore: registry,
    );

    final report = await startup.run();

    expect(report, isNotNull);
    expect(report!.successful, isTrue);
    expect(report.createdModels, 1);
    expect(models.snapshots.length, 1);
    expect(registry.registrations.length, 1);
  });

  test('richieste simultanee eseguono una sola preparazione', () async {
    var loads = 0;

    final models = SmartBetFrozenModelSnapshotStore();
    final registry = SmartBetFrozenModelRegistrationStore(clock: () => now);

    Future<List<SmartBetAnalysisRecord>> load() async {
      loads++;
      return history(50);
    }

    final startup = SmartBetShadowModelStartupService(
      loadHistory: load,
      clock: () => now,
      modelStore: models,
      registrationStore: registry,
    );

    final first = startup.run();
    final second = startup.run();

    expect(identical(first, second), isTrue);

    await Future.wait([first, second]);

    expect(loads, 1);
    expect(registry.registrations.length, 1);

    final restarted = SmartBetShadowModelStartupService(
      loadHistory: load,
      clock: () => now,
      modelStore: SmartBetFrozenModelSnapshotStore(),
      registrationStore: SmartBetFrozenModelRegistrationStore(clock: () => now),
    );

    final report = await restarted.run();

    expect(report!.createdModels, 0);
    expect(report.existingModels, 1);
  });

  test('errore di caricamento non blocca avvio app', () async {
    var attempts = 0;

    final startup = SmartBetShadowModelStartupService(
      loadHistory: () async {
        attempts++;
        throw StateError('Errore simulato');
      },
      clock: () => now,
    );

    final result = await startup.run();
    final repeated = await startup.run();

    expect(result, isNull);
    expect(repeated, isNull);
    expect(attempts, 1);
  });
}
