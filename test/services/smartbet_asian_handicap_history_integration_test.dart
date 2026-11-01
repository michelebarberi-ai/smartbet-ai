import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_asian_handicap_market_settlement_service.dart';
import 'package:smartbet_ai_new/services/smartbet_asian_handicap_settlement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final before = DateTime.utc(2026, 11, 1, 12);
  final kickoff = DateTime.utc(2026, 11, 3, 20);
  final finished = DateTime.utc(2026, 11, 4, 1);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SmartBetAnalysisRecord> resolved({
    required String market,
    double? odd = 2.40,
    int homeGoals = 2,
    int awayGoals = 1,
  }) async {
    final store = SmartBetAnalysisHistoryStore();

    await store.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.aiCoupon,
      fixtureId: 150001,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Test',
      country: 'Italia',
      matchDate: kickoff,
      market: market,
      probability: 0.55,
      smartScore: 73,
      quotedOdd: odd,
      recordedAt: before,
    );

    await store.registerActualResult(
      fixtureId: 150001,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      updatedAt: finished,
    );

    return store.records.single;
  }

  test('Handicap casa -0.75: mezza vittoria', () async {
    final record = await resolved(market: 'HCP ASIA CASA -0.75');

    expect(record.asianSettlement, SmartBetAsianSettlement.halfWin);
    expect(record.asianNetProfitUnits, closeTo(0.70, 1e-10));
    expect(record.status, SmartBetAnalysisStatus.unsupported);
    expect(record.resolvedAt, isNotNull);
  });

  test('Handicap casa -1: rimborso', () async {
    final record = await resolved(market: 'HCP ASIA CASA -1');

    expect(record.asianSettlement, SmartBetAsianSettlement.push);
    expect(record.asianNetProfitUnits, 0);
    expect(record.status, SmartBetAnalysisStatus.unsupported);
  });

  test('Handicap casa -1.25: mezza perdita', () async {
    final record = await resolved(market: 'HCP ASIA CASA -1.25');

    expect(record.asianSettlement, SmartBetAsianSettlement.halfLoss);
    expect(record.asianNetProfitUnits, -0.5);
  });

  test('Draw No Bet casa: pareggio rimborsato', () async {
    final record = await resolved(
      market: 'DNB CASA',
      homeGoals: 1,
      awayGoals: 1,
    );

    expect(record.asianSettlement, SmartBetAsianSettlement.push);
    expect(record.asianNetProfitUnits, 0);
  });

  test('Quota assente: liquidazione nota, profitto ignoto', () async {
    final record = await resolved(market: 'HCP ASIA CASA -0.75', odd: null);

    expect(record.asianSettlement, SmartBetAsianSettlement.halfWin);
    expect(record.asianNetProfitUnits, isNull);
  });

  test('Mercato classico conserva il comportamento binario', () async {
    final record = await resolved(market: '1');

    expect(record.status, SmartBetAnalysisStatus.correct);
    expect(record.asianSettlement, isNull);
    expect(record.asianNetProfitUnits, isNull);
  });

  test('Linea asiatica non valida non genera un esito inventato', () {
    final result = SmartBetAsianHandicapMarketSettlementService.evaluate(
      market: 'HCP ASIA CASA -0.3',
      homeGoals: 2,
      awayGoals: 1,
    );

    expect(result, isNull);
  });

  test('Liquidazione resta disponibile dopo riavvio store', () async {
    final record = await resolved(market: 'HCP ASIA OSPITE +1.25');

    expect(record.asianSettlement, SmartBetAsianSettlement.halfWin);

    final restoredStore = SmartBetAnalysisHistoryStore();
    await restoredStore.initialize();

    final restored = restoredStore.records.single;

    expect(restored.asianSettlement, SmartBetAsianSettlement.halfWin);
    expect(restored.quotedOdd, 2.40);
    expect(restored.asianNetProfitUnits, closeTo(0.70, 1e-10));
  });

  test('Vecchio record senza campo asiatico resta leggibile', () async {
    final record = await resolved(market: '1');

    final raw = record.toJson()..remove('asianSettlement');

    final restored = SmartBetAnalysisRecord.fromJson(raw);

    expect(restored, isNotNull);
    expect(restored!.asianSettlement, isNull);
    expect(restored.status, SmartBetAnalysisStatus.correct);
  });
}
