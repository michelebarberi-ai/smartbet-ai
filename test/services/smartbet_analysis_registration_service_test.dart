import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/models/analysis_result.dart';
import '../../lib/models/match_model.dart';
import '../../lib/services/dual_engine_analysis_service.dart';
import '../../lib/services/smartbet_analysis_comparison_store.dart';
import '../../lib/services/smartbet_analysis_history_store.dart';
import '../../lib/services/smartbet_analysis_registration_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final recordedAt = DateTime.utc(2026, 10, 21, 10);

  MatchModel match({
    int fixtureId = 100,
    String date = '2026-10-25T20:45:00Z',
  }) {
    return MatchModel(
      fixtureId: fixtureId,
      homeTeamId: 1,
      awayTeamId: 2,
      homeTeam: 'Inter',
      awayTeam: 'Roma',
      league: 'Serie A',
      leagueId: 135,
      country: 'Italy',
      countryCode: 'IT',
      date: date,
      leagueType: 'domestic',
      isEuropeanCup: false,
      isFriendly: false,
      isNational: false,
      aiWeight: 0.70,
      smartScore: 0,
      homeWin: 0,
      draw: 0,
      awayWin: 0,
      valueBet: '',
      odd: 0.0,
    );
  }

  AnalysisResult smartBet() {
    return const AnalysisResult(
      smartScore: 78,
      homeProbability: 55,
      drawProbability: 27,
      awayProbability: 18,
      over25Probability: 58,
      under25Probability: 42,
      goalProbability: 61,
      noGoalProbability: 39,
      prediction: '1',
      valueBet: '',
      risk: '',
      explanation: 'Test analysis',
    );
  }

  test('registra SmartBet e Diego come motori distinti', () async {
    final store = SmartBetAnalysisHistoryStore();

    final service = SmartBetAnalysisRegistrationService(store: store);

    final dual = DualEngineAnalysis(
      smartBet: smartBet(),

      // Non serve costruire tutto DiegoAiAnalysis:
      // il registratore usa il confronto prodotto dal Dual Engine.
      diego: null,

      comparison: const DualEngineComparison(
        status: DualEngineAgreement.diverge,
        smartBetMarket: '1X',
        diegoMarket: 'OVER 2.5',
        smartBetProbability: 0.72,
        diegoProbability: 0.61,
        diegoMarketConfidence: 74,
        diegoClassification: 'QUALIFIED VALUE',
      ),
    );

    await service.registerSelection(
      match: match(),
      smartBet: dual.smartBet,
      source: SmartBetAnalysisSource.analysis,
      dualAnalysis: dual,
      recordedAt: recordedAt,
    );

    expect(store.records.length, 2);

    final smartRecord = store.records.firstWhere(
      (record) => record.engine == SmartBetAnalysisEngine.smartBet,
    );

    final diegoRecord = store.records.firstWhere(
      (record) => record.engine == SmartBetAnalysisEngine.diego,
    );

    expect(smartRecord.market, '1X');
    expect(smartRecord.probability, 0.72);
    expect(smartRecord.smartScore, 78);

    expect(diegoRecord.market, 'OVER 2.5');
    expect(diegoRecord.probability, 0.61);
    expect(diegoRecord.confidence, 74);
    expect(diegoRecord.qualified, isTrue);
  });

  test('noSelection registra Diego come lettura non qualificata', () async {
    final store = SmartBetAnalysisHistoryStore();

    final service = SmartBetAnalysisRegistrationService(store: store);

    final dual = DualEngineAnalysis(
      smartBet: smartBet(),
      diego: null,
      comparison: const DualEngineComparison(
        status: DualEngineAgreement.noSelection,
        smartBetMarket: '1',
        diegoMarket: 'GOAL',
        smartBetProbability: 0.55,
        diegoProbability: 0.60,
        diegoMarketConfidence: 63,
        diegoClassification: 'NO VALUE',
      ),
    );

    await service.registerSelection(
      match: match(fixtureId: 200),
      smartBet: dual.smartBet,
      source: SmartBetAnalysisSource.dailyResults,
      dualAnalysis: dual,
      recordedAt: recordedAt,
    );

    expect(store.records.length, 2);

    final diegoRecord = store.records.firstWhere(
      (record) => record.engine == SmartBetAnalysisEngine.diego,
    );

    expect(diegoRecord.market, 'GOAL');
    expect(diegoRecord.probability, 0.60);
    expect(diegoRecord.confidence, 63);
    expect(diegoRecord.qualified, isFalse);
    expect(diegoRecord.classification, 'NO VALUE');
  });

  test('Diego unavailable non crea un record Diego', () async {
    final store = SmartBetAnalysisHistoryStore();

    final service = SmartBetAnalysisRegistrationService(store: store);

    final dual = DualEngineAnalysis(
      smartBet: smartBet(),
      diego: null,
      comparison: const DualEngineComparison(
        status: DualEngineAgreement.unavailable,
        smartBetMarket: '1',
        diegoMarket: 'N/D',
        smartBetProbability: 0.55,
      ),
    );

    await service.registerSelection(
      match: match(fixtureId: 300),
      smartBet: dual.smartBet,
      source: SmartBetAnalysisSource.analysis,
      dualAnalysis: dual,
      recordedAt: recordedAt,
    );

    expect(store.records.length, 1);

    expect(store.records.single.engine, SmartBetAnalysisEngine.smartBet);
  });

  test(
    'override mercato SmartBet usa mercato finale della schermata',
    () async {
      final store = SmartBetAnalysisHistoryStore();

      final service = SmartBetAnalysisRegistrationService(store: store);

      await service.registerSelection(
        match: match(fixtureId: 400),
        smartBet: smartBet(),
        source: SmartBetAnalysisSource.aiCoupon,
        smartBetMarket: 'X2',
        smartBetProbabilityPercent: 73,
        recordedAt: recordedAt,
      );

      expect(store.records.length, 1);

      final record = store.records.single;

      expect(record.market, 'X2');
      expect(record.probability, 0.73);
      expect(record.smartScore, 78);
    },
  );

  test('ripetizione aggrega la source senza duplicare', () async {
    final store = SmartBetAnalysisHistoryStore();

    final service = SmartBetAnalysisRegistrationService(store: store);

    await service.registerSelection(
      match: match(fixtureId: 500),
      smartBet: smartBet(),
      source: SmartBetAnalysisSource.aiCoupon,
      smartBetMarket: '1X',
      smartBetProbabilityPercent: 70,
      recordedAt: recordedAt,
    );

    await service.registerSelection(
      match: match(fixtureId: 500),
      smartBet: smartBet(),
      source: SmartBetAnalysisSource.combinations,
      smartBetMarket: '1X',
      smartBetProbabilityPercent: 90,
      recordedAt: recordedAt.add(const Duration(hours: 1)),
    );

    expect(store.records.length, 1);

    final record = store.records.single;

    expect(
      record.sources,
      containsAll([
        SmartBetAnalysisSource.aiCoupon,
        SmartBetAnalysisSource.combinations,
      ]),
    );

    // La prima previsione rimane quella statistica ufficiale.
    expect(record.probability, 0.70);
  });

  test('SmartBet e Diego con stesso mercato restano distinti', () async {
    final store = SmartBetAnalysisHistoryStore();

    final service = SmartBetAnalysisRegistrationService(store: store);

    final dual = DualEngineAnalysis(
      smartBet: smartBet(),
      diego: null,
      comparison: const DualEngineComparison(
        status: DualEngineAgreement.agree,
        smartBetMarket: 'GOAL',
        diegoMarket: 'GOAL',
        smartBetProbability: 0.61,
        diegoProbability: 0.64,
        diegoMarketConfidence: 71,
        diegoClassification: 'QUALIFIED VALUE',
      ),
    );

    await service.registerSelection(
      match: match(fixtureId: 550),
      smartBet: dual.smartBet,
      source: SmartBetAnalysisSource.combinations,
      dualAnalysis: dual,
      recordedAt: recordedAt,
    );

    expect(store.records.length, 2);

    expect(
      store.records
          .where((record) => record.engine == SmartBetAnalysisEngine.smartBet)
          .single
          .market,
      'GOAL',
    );

    expect(
      store.records
          .where((record) => record.engine == SmartBetAnalysisEngine.diego)
          .single
          .market,
      'GOAL',
    );
  });

  test('data partita non valida non registra nulla', () async {
    final store = SmartBetAnalysisHistoryStore();

    final service = SmartBetAnalysisRegistrationService(store: store);

    await service.registerSelection(
      match: match(fixtureId: 600, date: 'invalid-date'),
      smartBet: smartBet(),
      source: SmartBetAnalysisSource.analysis,
      smartBetMarket: '1',
      smartBetProbabilityPercent: 55,
      recordedAt: recordedAt,
    );

    expect(store.records, isEmpty);
  });

  test(
    'registrazione doppia crea automaticamente la coppia SmartBet Diego',
    () async {
      final store = SmartBetAnalysisHistoryStore();

      final comparisonStore = SmartBetAnalysisComparisonStore();

      final service = SmartBetAnalysisRegistrationService(
        store: store,
        comparisonStore: comparisonStore,
      );

      final dual = DualEngineAnalysis(
        smartBet: smartBet(),
        diego: null,
        comparison: const DualEngineComparison(
          status: DualEngineAgreement.diverge,
          smartBetMarket: '1X',
          diegoMarket: 'OVER 2.5',
          smartBetProbability: 0.72,
          diegoProbability: 0.61,
          diegoMarketConfidence: 74,
          diegoClassification: 'QUALIFIED VALUE',
        ),
      );

      await service.registerSelection(
        match: match(fixtureId: 800),
        smartBet: dual.smartBet,
        source: SmartBetAnalysisSource.analysis,
        dualAnalysis: dual,
        recordedAt: recordedAt,
      );

      expect(store.records.length, 2);
      expect(comparisonStore.links.length, 1);

      final link = comparisonStore.links.single;

      expect(link.fixtureId, 800);
      expect(link.smartBetMarket, '1X');
      expect(link.diegoMarket, 'OVER 2.5');

      expect(link.sources, [SmartBetAnalysisSource.analysis]);

      final smartRecord = store.records.firstWhere(
        (record) => record.engine == SmartBetAnalysisEngine.smartBet,
      );

      final diegoRecord = store.records.firstWhere(
        (record) => record.engine == SmartBetAnalysisEngine.diego,
      );

      expect(link.smartBetRecordKey, smartRecord.key);

      expect(link.diegoRecordKey, diegoRecord.key);
    },
  );
}
