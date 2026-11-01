import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_registration_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SmartBetAnalysisRecord record({
    required int id,
    required DateTime kickoff,
    required DateTime predictedAt,
    bool pending = false,
    bool correct = false,
    String market = 'GOAL',
  }) {
    final resolved = kickoff.add(const Duration(hours: 4));

    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
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
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: pending
          ? SmartBetAnalysisStatus.pending
          : correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: pending ? null : 2,
      actualAwayGoals: pending ? null : (correct ? 1 : 0),
      firstSeenAt: predictedAt,
      lastSeenAt: pending ? predictedAt : resolved,
      resolvedAt: pending ? null : resolved,
    );
  }

  Future<
    ({
      SmartBetFrozenModelRegistration registration,
      List<SmartBetAnalysisRecord> history,
      SmartBetAnalysisRecord pending,
    })
  >
  fixture({String market = 'GOAL'}) async {
    final now = DateTime.now().toUtc();

    final history = [
      for (var i = 0; i < 50; i++)
        record(
          id: i + 1000,
          kickoff: now
              .subtract(const Duration(days: 90))
              .add(Duration(days: i ~/ 2)),
          predictedAt: now
              .subtract(const Duration(days: 91))
              .add(Duration(days: i ~/ 2)),
          correct: i.isOdd,
        ),
    ];

    final snapshot = SmartBetFrozenModelSnapshot.prepare(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      frozenAt: now.subtract(const Duration(days: 40)),
      records: history,
    )!;

    final registry = SmartBetFrozenModelRegistrationStore(
      clock: () => now.subtract(const Duration(minutes: 2)),
    );

    final registration = await registry.register(snapshot);

    final pending = record(
      id: 99999,
      kickoff: now.add(const Duration(hours: 2)),
      predictedAt: now.subtract(const Duration(seconds: 15)),
      pending: true,
      market: market,
    );

    return (registration: registration, history: history, pending: pending);
  }

  test('associazione salvata con snapshot e ricaricata', () async {
    final data = await fixture();
    final store = SmartBetShadowLearningStore();

    final saved = await store.capture(
      record: data.pending,
      history: data.history,
      registeredShadowModel: data.registration,
    );

    expect(saved, isNotNull);
    expect(saved!.shadowModelId, data.registration.modelId);
    expect(saved.shadowModelLinkedAt, isNotNull);

    final reopened = SmartBetShadowLearningStore();
    await reopened.initialize();

    expect(
      reopened.predictions.single.shadowModelId,
      data.registration.modelId,
    );
  });

  test('snapshot esistente non acquisisce modello dopo', () async {
    final data = await fixture();
    final store = SmartBetShadowLearningStore();

    final original = await store.capture(
      record: data.pending,
      history: data.history,
    );

    final repeated = await store.capture(
      record: data.pending,
      history: data.history,
      registeredShadowModel: data.registration,
    );

    expect(original!.shadowModelId, isNull);
    expect(repeated!.shadowModelId, isNull);
    expect(store.predictions.length, 1);
  });

  test('modello di mercato diverso e JSON legacy', () async {
    final data = await fixture(market: 'OVER 2.5');
    final store = SmartBetShadowLearningStore();

    final saved = await store.capture(
      record: data.pending,
      history: data.history,
      registeredShadowModel: data.registration,
    );

    expect(saved, isNotNull);
    expect(saved!.shadowModelId, isNull);

    final oldJson = Map<String, dynamic>.from(saved.toJson())
      ..remove('shadowModelId')
      ..remove('shadowModelLinkedAt');

    final restored = SmartBetShadowPrediction.fromJson(oldJson);

    expect(restored.shadowModelId, isNull);
    expect(restored.shadowModelLinkedAt, isNull);
  });
}
