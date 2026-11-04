import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/goalvdline_central_learning_outbox.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  final current = DateTime.utc(2026, 11, 4, 11);
  DateTime now = current;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = current;
  });

  Future<GoalVdLineCentralLearningOutbox> createOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    return GoalVdLineCentralLearningOutbox(
      preferences: prefs,
      clock: () => now,
    );
  }

  Future<SmartBetAnalysisRecord> record({
    int fixture = 701,
    String market = 'OVER 2.5',
    double? probability = 0.7,
    DateTime? recordedAt,
    DateTime? kickoffAt,
  }) async {
    final store = SmartBetAnalysisHistoryStore();
    final result = await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: fixture,
      homeTeam: 'A',
      awayTeam: 'B',
      league: 'Test',
      country: 'Italy',
      matchDate: kickoffAt ?? current.add(const Duration(hours: 3)),
      market: market,
      probability: probability,
      recordedAt: recordedAt ?? now,
    );
    return result!;
  }

  test('P23B: consenso OFF, non raccoglie ne invia dati', () async {
    final outbox = await createOutbox();
    expect(await outbox.captureIfEligible(await record()), false);
    expect(outbox.consentGranted, false);
    expect(outbox.pendingCount, 0);
  });

  test('P23B: nuovo consenso, snapshot originale e deduplica', () async {
    final outbox = await createOutbox();
    await outbox.setConsent(true);
    final original = await record();
    expect(await outbox.captureIfEligible(original), true);
    expect(await outbox.captureIfEligible(original), false);
    expect(outbox.pendingCount, 1);
    final saved = outbox.pendingDrafts.single;
    expect(saved.probability, 0.7);
    expect(saved.engine, 'smartBet');
    expect(saved.fixtureId, 701);
    final reloaded = await createOutbox();
    expect((await reloaded.eligibleLocalDrafts()).single.key, saved.key);
  });

  test('P23B: consenso nuovo non include previsioni gia registrate', () async {
    final earlier = await record(recordedAt: current.subtract(const Duration(minutes: 2)));
    final outbox = await createOutbox();
    await outbox.setConsent(true);
    expect(await outbox.captureIfEligible(earlier), false);
  });

  test('P23B: revoca elimina la coda e disattiva la raccolta', () async {
    final outbox = await createOutbox();
    await outbox.setConsent(true);
    expect(await outbox.captureIfEligible(await record()), true);
    await outbox.setConsent(false);
    expect(outbox.consentGranted, false);
    expect(outbox.pendingCount, 0);
    final reloaded = await createOutbox();
    expect(await reloaded.eligibleLocalDrafts(), isEmpty);
    expect(reloaded.consentGranted, false);
  });

  test('P23B: scadenza prima del kickoff elimina il draft', () async {
    final outbox = await createOutbox();
    await outbox.setConsent(true);
    expect(await outbox.captureIfEligible(await record()), true);
    now = current.add(const Duration(hours: 3));
    expect(await outbox.eligibleLocalDrafts(), isEmpty);
  });

  test('P23B: esclude analisi retrodatate e partite gia iniziate', () async {
    final outbox = await createOutbox();
    await outbox.setConsent(true);
    expect(await outbox.captureIfEligible(await record(
      fixture: 702,
      recordedAt: current.subtract(const Duration(days: 1)),
    )), false);
    expect(await outbox.captureIfEligible(await record(
      fixture: 703,
      kickoffAt: current.subtract(const Duration(minutes: 1)),
    )), false);
  });
}
