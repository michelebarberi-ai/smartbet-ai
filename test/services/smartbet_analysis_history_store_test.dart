import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/smartbet_analysis_history_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final matchDate = DateTime.utc(2026, 10, 25, 20, 45);

  final firstSeen = DateTime.utc(2026, 10, 21, 10);

  test('deduplica stessa previsione e aggrega le source', () async {
    final store = SmartBetAnalysisHistoryStore();

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.aiCoupon,
      fixtureId: 100,
      homeTeam: 'Inter',
      awayTeam: 'Roma',
      league: 'Serie A',
      country: 'Italia',
      matchDate: matchDate,
      market: '1X',
      probability: 0.72,
      smartScore: 77,
      recordedAt: firstSeen,
    );

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.combinations,
      fixtureId: 100,
      homeTeam: 'Inter',
      awayTeam: 'Roma',
      league: 'Serie A',
      country: 'Italia',
      matchDate: matchDate,
      market: '  1x  ',
      probability: 0.91,
      smartScore: 99,
      recordedAt: firstSeen.add(const Duration(hours: 2)),
    );

    expect(store.records.length, 1);

    final record = store.records.single;

    expect(record.market, '1X');

    expect(
      record.sources,
      containsAll([
        SmartBetAnalysisSource.aiCoupon,
        SmartBetAnalysisSource.combinations,
      ]),
    );

    // Prima previsione immutabile.
    expect(record.probability, 0.72);
    expect(record.smartScore, 77);
  });

  test('SmartBet e Diego restano record distinti', () async {
    final store = SmartBetAnalysisHistoryStore();

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 200,
      homeTeam: 'Milan',
      awayTeam: 'Napoli',
      league: 'Serie A',
      country: 'Italia',
      matchDate: matchDate,
      market: '1',
      probability: 0.60,
      smartScore: 71,
      recordedAt: firstSeen,
    );

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.diego,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 200,
      homeTeam: 'Milan',
      awayTeam: 'Napoli',
      league: 'Serie A',
      country: 'Italia',
      matchDate: matchDate,
      market: 'X',
      probability: 0.38,
      confidence: 68,
      classification: 'QUALIFIED VALUE',
      qualified: true,
      recordedAt: firstSeen,
    );

    expect(store.records.length, 2);

    expect(
      store.records
          .where((record) => record.engine == SmartBetAnalysisEngine.smartBet)
          .length,
      1,
    );

    expect(
      store.records
          .where((record) => record.engine == SmartBetAnalysisEngine.diego)
          .length,
      1,
    );
  });

  test(
    'stesso motore può avere mercati diversi sulla stessa fixture',
    () async {
      final store = SmartBetAnalysisHistoryStore();

      await store.registerAnalysis(
        engine: SmartBetAnalysisEngine.smartBet,
        source: SmartBetAnalysisSource.analysis,
        fixtureId: 300,
        homeTeam: 'A',
        awayTeam: 'B',
        league: 'Test',
        country: 'Test',
        matchDate: matchDate,
        market: '1X',
        probability: 0.70,
        recordedAt: firstSeen,
      );

      await store.registerAnalysis(
        engine: SmartBetAnalysisEngine.smartBet,
        source: SmartBetAnalysisSource.dailyResults,
        fixtureId: 300,
        homeTeam: 'A',
        awayTeam: 'B',
        league: 'Test',
        country: 'Test',
        matchDate: matchDate,
        market: 'OVER 2.5',
        probability: 0.65,
        recordedAt: firstSeen,
      );

      expect(store.records.length, 2);
    },
  );

  test('risultato finale valuta SmartBet e Diego separatamente', () async {
    final store = SmartBetAnalysisHistoryStore();

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.aiCoupon,
      fixtureId: 400,
      homeTeam: 'A',
      awayTeam: 'B',
      league: 'Test',
      country: 'Test',
      matchDate: matchDate,
      market: '1X',
      probability: 0.75,
      recordedAt: firstSeen,
    );

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.diego,
      source: SmartBetAnalysisSource.aiCoupon,
      fixtureId: 400,
      homeTeam: 'A',
      awayTeam: 'B',
      league: 'Test',
      country: 'Test',
      matchDate: matchDate,
      market: 'OVER 2.5',
      probability: 0.58,
      confidence: 65,
      qualified: true,
      recordedAt: firstSeen,
    );

    final updated = await store.registerActualResult(
      fixtureId: 400,
      homeGoals: 1,
      awayGoals: 1,
    );

    expect(updated, 2);

    final smartBet = store.records.firstWhere(
      (record) => record.engine == SmartBetAnalysisEngine.smartBet,
    );

    final diego = store.records.firstWhere(
      (record) => record.engine == SmartBetAnalysisEngine.diego,
    );

    expect(smartBet.status, SmartBetAnalysisStatus.correct);

    expect(diego.status, SmartBetAnalysisStatus.wrong);
  });

  test('mercato non verificabile non viene contato come errore', () async {
    final store = SmartBetAnalysisHistoryStore();

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.diego,
      source: SmartBetAnalysisSource.combinations,
      fixtureId: 500,
      homeTeam: 'A',
      awayTeam: 'B',
      league: 'Test',
      country: 'Test',
      matchDate: matchDate,
      market: 'CASA SEGNA PRIMA',
      probability: 0.60,
      confidence: 61,
      qualified: false,
      recordedAt: firstSeen,
    );

    await store.registerActualResult(
      fixtureId: 500,
      homeGoals: 3,
      awayGoals: 1,
    );

    expect(store.records.single.status, SmartBetAnalysisStatus.unsupported);

    final stats = store.statsFor(SmartBetAnalysisEngine.diego);

    expect(stats.correct, 0);
    expect(stats.wrong, 0);
    expect(stats.unsupported, 1);
    expect(stats.accuracy, 0.0);
  });

  test('statistiche usano solo analisi prospettiche di default', () async {
    final store = SmartBetAnalysisHistoryStore();

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 600,
      homeTeam: 'A',
      awayTeam: 'B',
      league: 'Test',
      country: 'Test',
      matchDate: matchDate,
      market: '1',
      probability: 0.60,
      recordedAt: firstSeen,
    );

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 601,
      homeTeam: 'C',
      awayTeam: 'D',
      league: 'Test',
      country: 'Test',
      matchDate: matchDate,
      market: '2',
      probability: 0.55,
      recordedAt: matchDate.add(const Duration(minutes: 10)),
    );

    expect(store.statsFor(SmartBetAnalysisEngine.smartBet).analyzed, 1);

    expect(
      store
          .statsFor(SmartBetAnalysisEngine.smartBet, prospectiveOnly: false)
          .analyzed,
      2,
    );
  });

  test('persistenza mantiene record e metadati Diego', () async {
    final firstStore = SmartBetAnalysisHistoryStore();

    await firstStore.registerAnalysis(
      engine: SmartBetAnalysisEngine.diego,
      source: SmartBetAnalysisSource.dailyResults,
      fixtureId: 700,
      homeTeam: 'Juventus',
      awayTeam: 'Lazio',
      league: 'Serie A',
      country: 'Italia',
      matchDate: matchDate,
      market: 'GOAL',
      probability: 0.63,
      confidence: 74,
      classification: 'QUALIFIED VALUE',
      qualified: true,
      recordedAt: firstSeen,
    );

    final secondStore = SmartBetAnalysisHistoryStore();

    await secondStore.initialize();

    expect(secondStore.records.length, 1);

    final restored = secondStore.records.single;

    expect(restored.engine, SmartBetAnalysisEngine.diego);

    expect(restored.market, 'GOAL');
    expect(restored.confidence, 74);
    expect(restored.classification, 'QUALIFIED VALUE');
    expect(restored.qualified, isTrue);

    expect(restored.sources, [SmartBetAnalysisSource.dailyResults]);
  });
}
