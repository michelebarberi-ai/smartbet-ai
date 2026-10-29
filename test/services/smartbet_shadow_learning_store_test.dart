import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SmartBetAnalysisRecord makeRecord({
    required int id,
    DateTime? firstSeenAt,
    DateTime? matchDate,
    DateTime? resolvedAt,
    double? probability = 0.80,
    bool correct = true,
    bool pending = false,
    bool prospectiveEligible = true,
    String market = 'GOAL',
  }) {
    final first = firstSeenAt ?? DateTime.utc(2026, 9, 10);
    final match = matchDate ?? DateTime.utc(2026, 9, 11);
    final last = resolvedAt ?? first;

    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: id,
      homeTeam: 'Home',
      awayTeam: 'Away',
      league: 'Serie A',
      country: 'Italy',
      matchDate: match,
      market: market,
      probability: probability,
      smartScore: 70,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospectiveEligible,
      status: pending
          ? SmartBetAnalysisStatus.pending
          : correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: pending ? null : 2,
      actualAwayGoals: pending ? null : 1,
      firstSeenAt: first,
      lastSeenAt: last,
      resolvedAt: resolvedAt,
    );
  }

  List<SmartBetAnalysisRecord> history(int count) {
    return List.generate(
      count,
      (i) => makeRecord(
        id: i + 1,
        correct: i < count ~/ 2,
        resolvedAt: DateTime.utc(2026, 9, 12),
      ),
    );
  }

  SmartBetAnalysisRecord target({
    int id = 999,
    double probability = 0.80,
    bool prospectiveEligible = true,
    bool pending = true,
  }) {
    return makeRecord(
      id: id,
      firstSeenAt: DateTime.utc(2026, 10, 20),
      matchDate: DateTime.utc(2026, 10, 21),
      pending: pending,
      prospectiveEligible: prospectiveEligible,
      probability: probability,
    );
  }

  test('salva probabilita originale e calibrata', () async {
    final store = SmartBetShadowLearningStore();
    final prediction = target();

    final result = await store.capture(
      record: prediction,
      history: [...history(50), prediction],
    );

    expect(result, isNotNull);
    expect(result!.originalProbability, 0.80);
    expect(result.calibratedProbability, closeTo(0.70, 0.0001));
    expect(result.trainingSampleSize, 50);
    expect(result.calibrationApplied, true);
    expect(result.adjusted, true);
    expect(store.predictions.length, 1);
  });

  test('non modifica la prima previsione duplicata', () async {
    final store = SmartBetShadowLearningStore();

    final first = await store.capture(record: target(), history: history(50));

    final duplicate = await store.capture(
      record: target(probability: 0.40),
      history: history(50),
    );

    expect(first, isNotNull);
    expect(duplicate, isNotNull);
    expect(duplicate!.originalProbability, 0.80);
    expect(duplicate.calibratedProbability, first!.calibratedProbability);
    expect(store.predictions.length, 1);
  });

  test('le previsioni sopravvivono alla riapertura', () async {
    final firstStore = SmartBetShadowLearningStore();

    await firstStore.capture(record: target(), history: history(50));

    final reopenedStore = SmartBetShadowLearningStore();
    await reopenedStore.initialize();

    expect(reopenedStore.predictions.length, 1);

    final saved = reopenedStore.predictions.single;
    expect(saved.fixtureId, 999);
    expect(saved.originalProbability, 0.80);
    expect(saved.calibratedProbability, closeTo(0.70, 0.0001));
    expect(saved.trainingSampleSize, 50);
  });

  test('non utilizza risultati futuri', () async {
    final store = SmartBetShadowLearningStore();

    final futureResult = makeRecord(
      id: 500,
      resolvedAt: DateTime.utc(2026, 10, 23),
      correct: false,
    );

    final result = await store.capture(
      record: target(),
      history: [...history(49), futureResult],
    );

    expect(result, isNotNull);
    expect(result!.trainingSampleSize, 49);
    expect(result.calibrationApplied, false);
    expect(result.calibratedProbability, 0.80);
  });

  test('ignora previsioni non prospettiche o concluse', () async {
    final store = SmartBetShadowLearningStore();

    final late = await store.capture(
      record: target(prospectiveEligible: false),
      history: history(50),
    );

    final completed = await store.capture(
      record: target(id: 1000, pending: false),
      history: history(50),
    );

    expect(late, isNull);
    expect(completed, isNull);
    expect(store.predictions, isEmpty);
  });
  test('P15B: salva e ricarica la decisione adattiva', () async {
    final store = SmartBetShadowLearningStore();

    final result = await store.capture(
      record: target(),
      history: history(50),
      trialProbability: 0.70,
      trialEligible: true,
      decisionStatus: 'eligibleForTrial',
    );

    expect(result, isNotNull);
    expect(result!.trialEligible, true);
    expect(result.trialProbability, closeTo(0.70, 0.0001));
    expect(result.decisionStatus, 'eligibleForTrial');

    final reopened = SmartBetShadowLearningStore();
    await reopened.initialize();

    expect(reopened.predictions.length, 1);

    final saved = reopened.predictions.single;
    expect(saved.originalProbability, 0.80);
    expect(saved.calibratedProbability, closeTo(0.70, 0.0001));
    expect(saved.trialProbability, closeTo(0.70, 0.0001));
    expect(saved.trialEligible, true);
    expect(saved.decisionStatus, 'eligibleForTrial');
  });

  test('P15B: gate bloccato conserva originale', () async {
    final store = SmartBetShadowLearningStore();

    final result = await store.capture(
      record: target(),
      history: history(50),
      trialProbability: 0.80,
      trialEligible: false,
      decisionStatus: 'insufficientEvidence',
    );

    expect(result, isNotNull);
    expect(result!.calibratedProbability, closeTo(0.70, 0.0001));
    expect(result.trialProbability, 0.80);
    expect(result.trialEligible, false);
  });

  test('P15B: vecchi snapshot restano leggibili', () async {
    final store = SmartBetShadowLearningStore();

    await store.capture(record: target(), history: history(50));

    final json = store.predictions.single.toJson();

    json.remove('trialProbability');
    json.remove('trialEligible');
    json.remove('decisionStatus');

    final legacy = SmartBetShadowPrediction.fromJson(json);

    expect(legacy.originalProbability, 0.80);
    expect(legacy.trialProbability, isNull);
    expect(legacy.trialEligible, isNull);
    expect(legacy.decisionStatus, isNull);
  });

  test('P15B: blocca probabilita trial incoerente', () async {
    final store = SmartBetShadowLearningStore();

    await expectLater(
      store.capture(
        record: target(),
        history: history(50),
        trialProbability: 0.95,
        trialEligible: true,
        decisionStatus: 'eligibleForTrial',
      ),
      throwsA(isA<StateError>()),
    );

    expect(store.predictions, isEmpty);
  });

  test('P15B: impedisce decisioni incomplete', () async {
    final store = SmartBetShadowLearningStore();

    await expectLater(
      store.capture(
        record: target(),
        history: history(50),
        trialEligible: false,
      ),
      throwsA(isA<StateError>()),
    );

    expect(store.predictions, isEmpty);
  });

  test('P15B: non sovrascrive decisione iniziale', () async {
    final store = SmartBetShadowLearningStore();

    final first = await store.capture(
      record: target(),
      history: history(50),
      trialProbability: 0.70,
      trialEligible: true,
      decisionStatus: 'eligibleForTrial',
    );

    final duplicate = await store.capture(
      record: target(probability: 0.40),
      history: history(50),
      trialProbability: 0.40,
      trialEligible: false,
      decisionStatus: 'insufficientEvidence',
    );

    expect(first, isNotNull);
    expect(duplicate, isNotNull);
    expect(duplicate!.originalProbability, 0.80);
    expect(duplicate.trialEligible, true);
    expect(duplicate.decisionStatus, 'eligibleForTrial');
    expect(store.predictions.length, 1);
  });
}
