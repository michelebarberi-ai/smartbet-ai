import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/smartbet_analysis_comparison_store.dart';
import '../../lib/services/smartbet_analysis_history_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final kickoff = DateTime.utc(2026, 10, 25, 20, 45);

  final recordedAt = DateTime.utc(2026, 10, 21, 10);

  Future<SmartBetAnalysisRecord> register({
    required SmartBetAnalysisHistoryStore store,
    required SmartBetAnalysisEngine engine,
    required int fixtureId,
    required String market,
  }) async {
    final record = await store.registerAnalysis(
      engine: engine,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: fixtureId,
      homeTeam: 'Inter',
      awayTeam: 'Roma',
      league: 'Serie A',
      country: 'Italy',
      matchDate: kickoff,
      market: market,
      probability: 0.70,
      recordedAt: recordedAt,
    );

    expect(record, isNotNull);

    return record!;
  }

  test('registra una coppia SmartBet Diego', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final smart = await register(
      store: history,
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 100,
      market: '1X',
    );

    final diego = await register(
      store: history,
      engine: SmartBetAnalysisEngine.diego,
      fixtureId: 100,
      market: 'OVER 2.5',
    );

    final link = await comparisons.registerPair(
      smartBet: smart,
      diego: diego,
      source: SmartBetAnalysisSource.analysis,
      recordedAt: recordedAt,
    );

    expect(link, isNotNull);
    expect(comparisons.links.length, 1);

    expect(comparisons.links.single.smartBetMarket, '1X');

    expect(comparisons.links.single.diegoMarket, 'OVER 2.5');
  });

  test('stessa coppia aggrega le source', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final smart = await register(
      store: history,
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 200,
      market: 'GOAL',
    );

    final diego = await register(
      store: history,
      engine: SmartBetAnalysisEngine.diego,
      fixtureId: 200,
      market: 'GOAL',
    );

    await comparisons.registerPair(
      smartBet: smart,
      diego: diego,
      source: SmartBetAnalysisSource.aiCoupon,
      recordedAt: recordedAt,
    );

    await comparisons.registerPair(
      smartBet: smart,
      diego: diego,
      source: SmartBetAnalysisSource.combinations,
      recordedAt: recordedAt.add(const Duration(hours: 1)),
    );

    expect(comparisons.links.length, 1);

    expect(
      comparisons.links.single.sources,
      containsAll([
        SmartBetAnalysisSource.aiCoupon,
        SmartBetAnalysisSource.combinations,
      ]),
    );
  });

  test('più mercati sulla stessa fixture restano coppie distinte', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final smart1 = await register(
      store: history,
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 300,
      market: '1X',
    );

    final diego1 = await register(
      store: history,
      engine: SmartBetAnalysisEngine.diego,
      fixtureId: 300,
      market: 'GOAL',
    );

    final smart2 = await register(
      store: history,
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 300,
      market: 'OVER 2.5',
    );

    final diego2 = await register(
      store: history,
      engine: SmartBetAnalysisEngine.diego,
      fixtureId: 300,
      market: 'UNDER 3.5',
    );

    await comparisons.registerPair(
      smartBet: smart1,
      diego: diego1,
      source: SmartBetAnalysisSource.analysis,
    );

    await comparisons.registerPair(
      smartBet: smart2,
      diego: diego2,
      source: SmartBetAnalysisSource.combinations,
    );

    expect(comparisons.links.length, 2);
  });

  test('calcola confronto diretto corretto', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    Future<void> pair({
      required int fixtureId,
      required String smartMarket,
      required String diegoMarket,
      required int homeGoals,
      required int awayGoals,
    }) async {
      final smart = await register(
        store: history,
        engine: SmartBetAnalysisEngine.smartBet,
        fixtureId: fixtureId,
        market: smartMarket,
      );

      final diego = await register(
        store: history,
        engine: SmartBetAnalysisEngine.diego,
        fixtureId: fixtureId,
        market: diegoMarket,
      );

      await comparisons.registerPair(
        smartBet: smart,
        diego: diego,
        source: SmartBetAnalysisSource.analysis,
      );

      await history.registerActualResult(
        fixtureId: fixtureId,
        homeGoals: homeGoals,
        awayGoals: awayGoals,
      );
    }

    // Entrambi corretti.
    await pair(
      fixtureId: 401,
      smartMarket: '1X',
      diegoMarket: 'GOAL',
      homeGoals: 2,
      awayGoals: 1,
    );

    // Solo SmartBet.
    await pair(
      fixtureId: 402,
      smartMarket: '1',
      diegoMarket: 'X',
      homeGoals: 1,
      awayGoals: 0,
    );

    // Solo Diego.
    await pair(
      fixtureId: 403,
      smartMarket: '1',
      diegoMarket: 'X2',
      homeGoals: 0,
      awayGoals: 1,
    );

    // Entrambi errati.
    await pair(
      fixtureId: 404,
      smartMarket: '1',
      diegoMarket: 'OVER 2.5',
      homeGoals: 0,
      awayGoals: 0,
    );

    final stats = comparisons.calculateStats(analysisRecords: history.records);

    expect(stats.linkedPairs, 4);
    expect(stats.comparablePairs, 4);

    expect(stats.bothCorrect, 1);
    expect(stats.smartBetOnlyCorrect, 1);
    expect(stats.diegoOnlyCorrect, 1);
    expect(stats.bothWrong, 1);

    expect(stats.smartBetCorrect, 2);
    expect(stats.diegoCorrect, 2);

    expect(stats.smartBetAccuracy, 50.0);
    expect(stats.diegoAccuracy, 50.0);
  });

  test('pending e unsupported non falsano il confronto', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final pendingSmart = await register(
      store: history,
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 500,
      market: '1X',
    );

    final pendingDiego = await register(
      store: history,
      engine: SmartBetAnalysisEngine.diego,
      fixtureId: 500,
      market: 'GOAL',
    );

    await comparisons.registerPair(
      smartBet: pendingSmart,
      diego: pendingDiego,
      source: SmartBetAnalysisSource.analysis,
    );

    final unsupportedSmart = await register(
      store: history,
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 501,
      market: '1X',
    );

    final unsupportedDiego = await register(
      store: history,
      engine: SmartBetAnalysisEngine.diego,
      fixtureId: 501,
      market: 'CASA SEGNA PRIMA',
    );

    await comparisons.registerPair(
      smartBet: unsupportedSmart,
      diego: unsupportedDiego,
      source: SmartBetAnalysisSource.analysis,
    );

    await history.registerActualResult(
      fixtureId: 501,
      homeGoals: 2,
      awayGoals: 1,
    );

    final stats = comparisons.calculateStats(analysisRecords: history.records);

    expect(stats.linkedPairs, 2);
    expect(stats.comparablePairs, 0);

    expect(stats.pendingPairs, 1);
    expect(stats.unsupportedPairs, 1);

    expect(stats.smartBetAccuracy, 0.0);
    expect(stats.diegoAccuracy, 0.0);
  });

  test('persistenza conserva le coppie', () async {
    final history = SmartBetAnalysisHistoryStore();

    final first = SmartBetAnalysisComparisonStore();

    final smart = await register(
      store: history,
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 600,
      market: '1X',
    );

    final diego = await register(
      store: history,
      engine: SmartBetAnalysisEngine.diego,
      fixtureId: 600,
      market: 'GOAL',
    );

    await first.registerPair(
      smartBet: smart,
      diego: diego,
      source: SmartBetAnalysisSource.dailyResults,
      recordedAt: recordedAt,
    );

    final second = SmartBetAnalysisComparisonStore();

    await second.initialize();

    expect(second.links.length, 1);

    final restored = second.links.single;

    expect(restored.fixtureId, 600);
    expect(restored.smartBetMarket, '1X');
    expect(restored.diegoMarket, 'GOAL');

    expect(restored.sources, [SmartBetAnalysisSource.dailyResults]);
  });
}
