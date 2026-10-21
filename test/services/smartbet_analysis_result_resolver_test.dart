import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/smartbet_analysis_history_store.dart';
import '../../lib/services/smartbet_analysis_result_resolver.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> register({
    required SmartBetAnalysisHistoryStore store,
    required int fixtureId,
    required SmartBetAnalysisEngine engine,
    required String market,
    required DateTime kickoff,
  }) {
    return store
        .registerAnalysis(
          engine: engine,
          source: SmartBetAnalysisSource.combinations,
          fixtureId: fixtureId,
          homeTeam: 'Home $fixtureId',
          awayTeam: 'Away $fixtureId',
          league: 'Test League',
          country: 'Test',
          matchDate: kickoff,
          market: market,
          probability: 0.70,
          smartScore: engine == SmartBetAnalysisEngine.smartBet ? 75 : null,
          confidence: engine == SmartBetAnalysisEngine.diego ? 72 : null,
          qualified: engine == SmartBetAnalysisEngine.diego ? true : null,
          recordedAt: kickoff.subtract(const Duration(days: 1)),
        )
        .then((_) {});
  }

  Map<String, dynamic> fixture({
    required int id,
    required String status,
    int? homeGoals,
    int? awayGoals,
    int? fulltimeHome,
    int? fulltimeAway,
  }) {
    return {
      'fixture': {
        'id': id,
        'status': {'short': status},
      },
      'goals': {'home': homeGoals, 'away': awayGoals},
      'score': {
        'fulltime': {'home': fulltimeHome, 'away': fulltimeAway},
      },
    };
  }

  test('una fixture aggiorna tutti i record SmartBet e Diego', () async {
    final store = SmartBetAnalysisHistoryStore();

    final kickoff = DateTime.utc(2026, 10, 20, 18);

    await register(
      store: store,
      fixtureId: 100,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      kickoff: kickoff,
    );

    await register(
      store: store,
      fixtureId: 100,
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'OVER 2.5',
      kickoff: kickoff,
    );

    await register(
      store: store,
      fixtureId: 100,
      engine: SmartBetAnalysisEngine.diego,
      market: 'X',
      kickoff: kickoff,
    );

    await register(
      store: store,
      fixtureId: 100,
      engine: SmartBetAnalysisEngine.diego,
      market: 'GOAL',
      kickoff: kickoff,
    );

    var calls = 0;

    final resolver = SmartBetAnalysisResultResolver(
      store: store,
      fetchByDate: (_) async {
        calls++;

        return [fixture(id: 100, status: 'FT', homeGoals: 2, awayGoals: 1)];
      },
    );

    final summary = await resolver.resolvePending(
      now: kickoff.add(const Duration(hours: 5)),
    );

    expect(calls, 1);

    expect(summary.pendingRecordsBefore, 4);
    expect(summary.pendingFixturesBefore, 1);
    expect(summary.eligibleFixtures, 1);

    expect(summary.resolvedFixtures, 1);
    expect(summary.updatedRecords, 4);

    expect(summary.pendingRecordsAfter, 0);
    expect(summary.pendingFixturesAfter, 0);

    final records = store.recordsForFixture(100);

    expect(
      records
          .where((record) => record.status == SmartBetAnalysisStatus.correct)
          .length,
      3,
    );

    expect(
      records
          .where((record) => record.status == SmartBetAnalysisStatus.wrong)
          .length,
      1,
    );
  });

  test('fixture troppo recente non viene interrogata', () async {
    final store = SmartBetAnalysisHistoryStore();

    final kickoff = DateTime.utc(2026, 10, 21, 18);

    await register(
      store: store,
      fixtureId: 200,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1',
      kickoff: kickoff,
    );

    var calls = 0;

    final resolver = SmartBetAnalysisResultResolver(
      store: store,
      fetchByDate: (_) async {
        calls++;
        return [];
      },
    );

    final summary = await resolver.resolvePending(
      now: kickoff.add(const Duration(hours: 2)),
    );

    expect(calls, 0);
    expect(summary.eligibleFixtures, 0);
    expect(summary.skippedNotDue, 1);
    expect(summary.pendingRecordsAfter, 1);
  });

  test('stato non finale lascia il record pending', () async {
    final store = SmartBetAnalysisHistoryStore();

    final kickoff = DateTime.utc(2026, 10, 20, 18);

    await register(
      store: store,
      fixtureId: 300,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1',
      kickoff: kickoff,
    );

    final resolver = SmartBetAnalysisResultResolver(
      store: store,
      fetchByDate: (_) async {
        return [fixture(id: 300, status: '2H', homeGoals: 1, awayGoals: 0)];
      },
    );

    final summary = await resolver.resolvePending(
      now: kickoff.add(const Duration(hours: 5)),
    );

    expect(summary.resolvedFixtures, 0);

    expect(store.records.single.status, SmartBetAnalysisStatus.pending);
  });

  test('AET usa fulltime regolamentare e non score dopo extra time', () async {
    final store = SmartBetAnalysisHistoryStore();

    final kickoff = DateTime.utc(2026, 10, 20, 18);

    await register(
      store: store,
      fixtureId: 400,
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'X',
      kickoff: kickoff,
    );

    final resolver = SmartBetAnalysisResultResolver(
      store: store,
      fetchByDate: (_) async {
        return [
          fixture(
            id: 400,
            status: 'AET',

            // Risultato dopo supplementari.
            homeGoals: 2,
            awayGoals: 1,

            // 90 minuti.
            fulltimeHome: 1,
            fulltimeAway: 1,
          ),
        ];
      },
    );

    await resolver.resolvePending(now: kickoff.add(const Duration(hours: 5)));

    expect(store.records.single.status, SmartBetAnalysisStatus.correct);

    expect(store.records.single.actualHomeGoals, 1);

    expect(store.records.single.actualAwayGoals, 1);
  });

  test('PEN senza fulltime resta pending invece di indovinare', () async {
    final store = SmartBetAnalysisHistoryStore();

    final kickoff = DateTime.utc(2026, 10, 20, 18);

    await register(
      store: store,
      fixtureId: 500,
      engine: SmartBetAnalysisEngine.diego,
      market: '1X',
      kickoff: kickoff,
    );

    final resolver = SmartBetAnalysisResultResolver(
      store: store,
      fetchByDate: (_) async {
        return [fixture(id: 500, status: 'PEN', homeGoals: 5, awayGoals: 4)];
      },
    );

    final summary = await resolver.resolvePending(
      now: kickoff.add(const Duration(hours: 5)),
    );

    expect(summary.resolvedFixtures, 0);

    expect(store.records.single.status, SmartBetAnalysisStatus.pending);
  });

  test('più fixture della stessa data causano una sola fetch', () async {
    final store = SmartBetAnalysisHistoryStore();

    final kickoff = DateTime.utc(2026, 10, 20, 18);

    await register(
      store: store,
      fixtureId: 600,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1',
      kickoff: kickoff,
    );

    await register(
      store: store,
      fixtureId: 601,
      engine: SmartBetAnalysisEngine.diego,
      market: '2',
      kickoff: kickoff.add(const Duration(hours: 1)),
    );

    var calls = 0;

    final resolver = SmartBetAnalysisResultResolver(
      store: store,
      fetchByDate: (_) async {
        calls++;

        return [
          fixture(id: 600, status: 'FT', homeGoals: 1, awayGoals: 0),
          fixture(id: 601, status: 'FT', homeGoals: 0, awayGoals: 2),
        ];
      },
    );

    final summary = await resolver.resolvePending(
      now: kickoff.add(const Duration(hours: 7)),
    );

    expect(calls, 1);
    expect(summary.datesQueried, 1);
    expect(summary.resolvedFixtures, 2);
    expect(summary.updatedRecords, 2);
    expect(summary.pendingRecordsAfter, 0);
  });

  test('errore API non altera lo storico', () async {
    final store = SmartBetAnalysisHistoryStore();

    final kickoff = DateTime.utc(2026, 10, 20, 18);

    await register(
      store: store,
      fixtureId: 700,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      kickoff: kickoff,
    );

    final resolver = SmartBetAnalysisResultResolver(
      store: store,
      fetchByDate: (_) async {
        throw Exception('network');
      },
    );

    final summary = await resolver.resolvePending(
      now: kickoff.add(const Duration(hours: 5)),
    );

    expect(summary.apiErrors, 1);
    expect(summary.resolvedFixtures, 0);
    expect(summary.pendingRecordsAfter, 1);

    expect(store.records.single.status, SmartBetAnalysisStatus.pending);
  });
}
