import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_registration_store.dart';

void main() {
  final registeredAt = DateTime.utc(2026, 10, 1);
  final frozenAt = DateTime.utc(2026, 9, 1);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SmartBetFrozenModelRegistrationStore store() =>
      SmartBetFrozenModelRegistrationStore(clock: () => registeredAt);

  SmartBetFrozenModelSnapshot model({
    double probability = 0.8,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  }) {
    final records = <SmartBetAnalysisRecord>[];

    for (var i = 0; i < 50; i++) {
      final kickoff = DateTime.utc(2026, 8, 1, 18).add(Duration(days: i ~/ 2));

      records.add(
        SmartBetAnalysisRecord(
          engine: engine,
          fixtureId: i + 1000,
          homeTeam: 'Casa',
          awayTeam: 'Ospite',
          league: 'Test',
          country: 'Test',
          matchDate: kickoff,
          market: 'GOAL',
          probability: probability,
          smartScore: 80,
          confidence: null,
          classification: null,
          qualified: engine == SmartBetAnalysisEngine.diego ? true : null,
          sources: const [SmartBetAnalysisSource.analysis],
          prospectiveEligible: true,
          status: i.isOdd
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong,
          actualHomeGoals: 2,
          actualAwayGoals: i.isOdd ? 1 : 0,
          firstSeenAt: kickoff.subtract(const Duration(hours: 12)),
          lastSeenAt: kickoff.add(const Duration(hours: 4)),
          resolvedAt: kickoff.add(const Duration(hours: 4)),
        ),
      );
    }

    return SmartBetFrozenModelSnapshot.prepare(
      engine: engine,
      market: 'GOAL',
      frozenAt: frozenAt,
      records: records,
    )!;
  }

  test('registra modello e orario originale', () async {
    final repository = store();
    final result = await repository.register(model());

    expect(result.registeredAt, registeredAt);
    expect(result.model.trainingFixtures, 50);
    expect(repository.registrations.length, 1);
  });

  test('la riapertura conserva registrazione e modello', () async {
    final first = store();
    final saved = await first.register(model());

    final reopened = store();
    await reopened.initialize();

    expect(reopened.registrations.length, 1);
    expect(reopened.registrations.single.modelId, saved.modelId);
    expect(reopened.registrations.single.registeredAt, registeredAt);
  });

  test('registrare due volte non cambia orario', () async {
    final repository = store();
    final snapshot = model();

    await repository.register(snapshot);
    await repository.register(snapshot);

    expect(repository.registrations.length, 1);
    expect(repository.registrations.single.registeredAt, registeredAt);
  });

  test('stesso ID con correzione differente viene bloccato', () async {
    final repository = store();

    final first = model(probability: 0.8);
    final changed = model(probability: 0.6);

    expect(first.id, changed.id);
    expect(first.adjustment, isNot(changed.adjustment));

    await repository.register(first);

    await expectLater(repository.register(changed), throwsStateError);

    expect(repository.registrations.single.model.adjustment, first.adjustment);
  });

  test('una data futura di congelamento viene respinta', () async {
    final snapshot = model();
    final earlyStore = SmartBetFrozenModelRegistrationStore(
      clock: () => DateTime.utc(2026, 8, 30),
    );

    await expectLater(earlyStore.register(snapshot), throwsStateError);
  });

  test('solo previsioni successive sono ammissibili', () async {
    final repository = store();
    final snapshot = model();
    await repository.register(snapshot);

    bool eligible(
      DateTime predictedAt, {
      SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    }) => repository.registeredBeforePrediction(
      modelId: snapshot.id,
      engine: engine,
      market: 'GOAL',
      predictedAt: predictedAt,
    );

    expect(eligible(DateTime.utc(2026, 10, 2)), isTrue);
    expect(eligible(DateTime.utc(2026, 9, 30)), isFalse);
    expect(eligible(registeredAt), isFalse);

    expect(
      eligible(DateTime.utc(2026, 10, 2), engine: SmartBetAnalysisEngine.diego),
      isFalse,
    );
  });

  test('vecchi snapshot senza registrazione non sono autorizzati', () async {
    final snapshot = model();
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      SmartBetFrozenModelSnapshotStore.storageKey,
      jsonEncode([snapshot.toJson()]),
    );

    final repository = store();
    await repository.initialize();

    expect(repository.registrations, isEmpty);

    expect(
      repository.registeredBeforePrediction(
        modelId: snapshot.id,
        engine: SmartBetAnalysisEngine.smartBet,
        market: 'GOAL',
        predictedAt: DateTime.utc(2026, 10, 2),
      ),
      isFalse,
    );
  });
}
