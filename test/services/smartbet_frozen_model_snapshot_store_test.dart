import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_frozen_model_snapshot_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final cutoff = DateTime.utc(2026, 9, 1);

  SmartBetAnalysisRecord record(
    int id, {
    double probability = 0.8,
    bool correct = true,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    bool qualified = true,
    DateTime? resolvedAt,
  }) {
    final kickoff = DateTime.utc(2026, 8, 1, 18).add(Duration(days: id ~/ 2));

    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: id + 1000,
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

  List<SmartBetAnalysisRecord> history({double probability = 0.8}) => [
    for (var i = 0; i < 50; i++)
      record(i, probability: probability, correct: i.isOdd),
  ];

  SmartBetFrozenModelSnapshot? prepare(
    Iterable<SmartBetAnalysisRecord> records, {
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  }) => SmartBetFrozenModelSnapshot.prepare(
    engine: engine,
    market: 'GOAL',
    frozenAt: cutoff,
    records: records,
  );

  test('50 risultati precedenti producono uno snapshot', () {
    final model = prepare(history());

    expect(model, isNotNull);
    expect(model!.trainingFixtures, 50);
    expect(model.adjustment, closeTo(-0.10, 1e-9));
    expect(model.calibratedProbability(0.8), closeTo(0.70, 1e-9));
  });

  test('49 risultati non creano un modello', () {
    expect(prepare(history().take(49)), isNull);
  });

  test('risultati successivi al congelamento esclusi', () {
    final records = history().take(49).toList()
      ..add(record(49, resolvedAt: DateTime.utc(2026, 9, 2)));

    expect(prepare(records), isNull);
  });

  test('Diego non qualificato non entra nel modello', () {
    final records = [
      for (var i = 0; i < 50; i++)
        record(i, engine: SmartBetAnalysisEngine.diego, qualified: false),
    ];

    expect(prepare(records, engine: SmartBetAnalysisEngine.diego), isNull);
  });

  test('salvataggio e riapertura mantengono il modello', () async {
    final model = prepare(history())!;
    final store = SmartBetFrozenModelSnapshotStore();

    await store.save(model);

    final reopened = SmartBetFrozenModelSnapshotStore();
    await reopened.initialize();

    expect(reopened.snapshots.length, 1);
    expect(reopened.snapshots.single.id, model.id);
    expect(reopened.snapshots.single.adjustment, model.adjustment);

    await reopened.save(model);
    expect(reopened.snapshots.length, 1);
  });

  test('stesso identificativo non può cambiare correzione', () async {
    final first = prepare(history(probability: 0.8))!;
    final altered = prepare(history(probability: 0.6))!;

    expect(first.id, altered.id);
    expect(first.adjustment, isNot(altered.adjustment));

    final store = SmartBetFrozenModelSnapshotStore();
    await store.save(first);

    await expectLater(store.save(altered), throwsStateError);

    expect(store.snapshots.single.adjustment, first.adjustment);
  });

  test('JSON alterato viene rifiutato', () {
    final model = prepare(history())!;
    final json = model.toJson();

    json['adjustment'] = 0.75;

    expect(
      () => SmartBetFrozenModelSnapshot.fromJson(json),
      throwsFormatException,
    );
  });
}
