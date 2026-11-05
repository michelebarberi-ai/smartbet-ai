import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/goalvdline_central_learning_outbox.dart';
import 'package:smartbet_ai_new/services/goalvdline_historical_learning_review.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 11);
  final oldKickoff = DateTime.utc(2026, 10, 25, 20);
  final oldFirstSeen = DateTime.utc(2026, 10, 23, 10);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SmartBetAnalysisRecord> createRecord(
    SmartBetAnalysisHistoryStore store, {
    int fixtureId = 100,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'OVER 2.5',
    double? probability = 0.7,
    DateTime? kickoff,
    DateTime? firstSeen,
    bool withOutcome = false,
  }) async {
    final record = await store.registerAnalysis(
      engine: engine,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: fixtureId,
      homeTeam: 'A',
      awayTeam: 'B',
      league: 'Test',
      country: 'Test',
      matchDate: kickoff ?? oldKickoff,
      market: market,
      probability: probability,
      recordedAt: firstSeen ?? oldFirstSeen,
    );
    if (withOutcome) {
      await store.registerActualResult(
        fixtureId: fixtureId,
        homeGoals: 3,
        awayGoals: 0,
        updatedAt: oldKickoff.add(const Duration(hours: 3)),
      );
      return store.records.firstWhere((r) => r.key == record!.key);
    }
    return record!;
  }

  Future<GoalVdLineHistoricalLearningReview> review() async {
    final prefs = await SharedPreferences.getInstance();
    return GoalVdLineHistoricalLearningReview(
      preferences: prefs,
      clock: () => now,
    );
  }

  test('P23B3: audit locale conta record e partite senza opt-in', () async {
    final store = SmartBetAnalysisHistoryStore();
    await createRecord(store, fixtureId: 1, withOutcome: true);
    await createRecord(store, fixtureId: 1, market: '1X');
    await createRecord(
      store,
      fixtureId: 2,
      firstSeen: oldKickoff.add(const Duration(hours: 1)),
    );
    await createRecord(
      store,
      fixtureId: 3,
      kickoff: now.add(const Duration(days: 1)),
      firstSeen: now.subtract(const Duration(hours: 1)),
    );
    final service = await review();
    final audit = service.audit(store.records);
    expect(audit.total, 4);
    expect(audit.uniqueFixtures, 3);
    expect(audit.settledCandidates, 1);
    expect(audit.awaitingResult, 1);
    expect(audit.excluded, 1);
    expect(audit.futureFixtures, 1);
    expect(service.consentGranted, false);
    expect(service.preparedCount, 0);
  });

  test(
    'P23B3: copia solo retrospettive valide, senza cambiare storico',
    () async {
      final store = SmartBetAnalysisHistoryStore();
      await createRecord(store, fixtureId: 10, withOutcome: true);
      await createRecord(
        store,
        fixtureId: 11,
        engine: SmartBetAnalysisEngine.diego,
      );
      await createRecord(store, fixtureId: 12, probability: null);
      await createRecord(
        store,
        fixtureId: 13,
        firstSeen: oldKickoff.add(const Duration(hours: 1)),
      );
      final original = store.records.map((r) => r.toJson().toString()).toList();
      final service = await review();
      final count = await service.prepareFromHistory(store.records);
      expect(count, 2);
      expect(service.consentGranted, true);
      final snapshots = service.preparedDrafts;
      expect(snapshots.map((r) => r.fixtureId).toSet(), {10, 11});
      expect(snapshots.firstWhere((r) => r.fixtureId == 10).probability, 0.7);
      expect(
        snapshots.firstWhere((r) => r.fixtureId == 10).firstSeenAt,
        oldFirstSeen,
      );
      expect(
        store.records.map((r) => r.toJson().toString()).toList(),
        original,
      );
      final reloaded = await review();
      await reloaded.initialize();
      expect(reloaded.preparedCount, 2);
      expect(reloaded.preparedDrafts.first.localStatusHint, isNotEmpty);
    },
  );

  test('P23B3: seconda preparazione e idempotente, cutoff invariato', () async {
    final store = SmartBetAnalysisHistoryStore();
    await createRecord(store, fixtureId: 21);
    final service = await review();
    expect(await service.prepareFromHistory(store.records), 1);
    expect(await service.prepareFromHistory(store.records), 1);
    // La nuova registrazione e' successiva al primo consenso retro.
    await createRecord(
      store,
      fixtureId: 22,
      kickoff: now.subtract(const Duration(minutes: 30)),
      firstSeen: now.add(const Duration(minutes: 1)),
    );
    expect(await service.prepareFromHistory(store.records), 1);
  });

  test('P23B3: revoca elimina copia, non storico ne coda live', () async {
    final store = SmartBetAnalysisHistoryStore();
    await createRecord(store, fixtureId: 31, withOutcome: true);
    final service = await review();
    await service.prepareFromHistory(store.records);
    final outbox = GoalVdLineCentralLearningOutbox(
      preferences: await SharedPreferences.getInstance(),
      clock: () => now,
    );
    await outbox.setConsent(true);
    expect(outbox.consentGranted, true);
    await service.deletePrepared();
    expect(service.preparedCount, 0);
    expect(service.consentGranted, false);
    expect(store.records.length, 1);
    expect(outbox.consentGranted, true);
    final reloaded = await review();
    await reloaded.initialize();
    expect(reloaded.preparedCount, 0);
  });

  test(
    'P23B3: snapshot non entra mai nella coda delle nuove previsioni',
    () async {
      final store = SmartBetAnalysisHistoryStore();
      await createRecord(store, fixtureId: 41, withOutcome: true);
      final service = await review();
      await service.prepareFromHistory(store.records);
      final outbox = GoalVdLineCentralLearningOutbox(
        preferences: await SharedPreferences.getInstance(),
        clock: () => now,
      );
      await outbox.initialize();
      expect(outbox.consentGranted, false);
      expect(outbox.pendingCount, 0);
      expect(service.preparedCount, 1);
    },
  );
}
