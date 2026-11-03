import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_registration_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_capture_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final before = DateTime.utc(2026, 10, 21, 10);
  final after = DateTime.utc(2026, 11, 25, 10);

  MatchModel match(int fixtureId) => MatchModel(
    fixtureId: fixtureId,
    homeTeamId: 10,
    awayTeamId: 11,
    homeTeam: 'Casa',
    awayTeam: 'Ospite',
    league: 'Serie A',
    leagueId: 135,
    country: 'Italia',
    countryCode: 'IT',
    date: '2026-11-20T20:00:00Z',
    leagueType: 'domestic',
    isEuropeanCup: false,
    isFriendly: false,
    isNational: false,
    aiWeight: 0.8,
    smartScore: 0,
    homeWin: 0,
    draw: 0,
    awayWin: 0,
    valueBet: '',
    odd: 0,
  );

  AnalysisResult prediction({
    double homeXg = 1.4,
    double awayXg = 1.0,
    int drawProbability = 27,
  }) => AnalysisResult(
    smartScore: 74,
    homeProbability: 50,
    drawProbability: drawProbability,
    awayProbability: 50 - drawProbability,
    over15Probability: 68,
    under15Probability: 32,
    over25Probability: 48,
    under25Probability: 52,
    goalProbability: 59,
    noGoalProbability: 41,
    expectedHomeGoals: homeXg,
    expectedAwayGoals: awayXg,
    dataConfidence: 76,
    prediction: '1',
    valueBet: '',
    risk: '',
    explanation: 'previsione di test',
  );

  test('P21C: registra tutte le probabilita native, soprattutto X', () async {
    final shadows = SmartBetSimulationShadowStore();
    final registration = SmartBetAnalysisRegistrationService(
      store: SmartBetAnalysisHistoryStore(),
      simulationCapture: SmartBetSimulationShadowCaptureService(store: shadows),
    );
    await registration.registerSelection(
      match: match(2101),
      smartBet: prediction(),
      source: SmartBetAnalysisSource.analysis,
      smartBetMarket: 'X',
      smartBetProbabilityPercent: 27,
      recordedAt: before,
    );
    expect(shadows.snapshots, hasLength(1));
    final snap = shadows.snapshots.single;
    expect(snap.engine, 'SMARTBET');
    expect(snap.fixtureId, 2101);
    expect(snap.capturedAt, before);
    expect(snap.dataQuality, closeTo(0.76, 1e-12));
    expect(snap.originalProbabilities['X'], 0.27);
    expect(snap.simulatedProbabilities['X'], isNotNull);
    expect(snap.originalProbabilities['OVER 2.5'], 0.48);
    expect(snap.originalProbabilities['GOAL'], 0.59);
    expect(snap.simulatedProbabilities.keys, contains('OVER 4.5'));
    expect(
      snap.simulatedProbabilities.length,
      snap.originalProbabilities.length,
    );
  });

  test('P21C: analisi ripetuta NON sovrascrive il primo snapshot', () async {
    final shadows = SmartBetSimulationShadowStore();
    final registration = SmartBetAnalysisRegistrationService(
      store: SmartBetAnalysisHistoryStore(),
      simulationCapture: SmartBetSimulationShadowCaptureService(store: shadows),
    );
    await registration.registerSelection(
      match: match(2102),
      smartBet: prediction(),
      source: SmartBetAnalysisSource.analysis,
      smartBetMarket: 'X',
      smartBetProbabilityPercent: 27,
      recordedAt: before,
    );
    await registration.registerSelection(
      match: match(2102),
      smartBet: prediction(homeXg: 2.4, drawProbability: 10),
      source: SmartBetAnalysisSource.combinations,
      smartBetMarket: 'X',
      smartBetProbabilityPercent: 10,
      recordedAt: before.add(const Duration(hours: 2)),
    );
    expect(shadows.snapshots, hasLength(1));
    expect(shadows.snapshots.single.expectedHomeGoals, 1.4);
    expect(shadows.snapshots.single.originalProbabilities['X'], 0.27);
  });

  test('P21C: richieste dopo calcio inizio non creano snapshot', () async {
    final shadows = SmartBetSimulationShadowStore();
    final registration = SmartBetAnalysisRegistrationService(
      store: SmartBetAnalysisHistoryStore(),
      simulationCapture: SmartBetSimulationShadowCaptureService(store: shadows),
    );
    await registration.registerSelection(
      match: match(2103),
      smartBet: prediction(),
      source: SmartBetAnalysisSource.analysis,
      smartBetMarket: '1',
      recordedAt: after,
    );
    expect(shadows.snapshots, isEmpty);
  });

  test(
    'P21C: xG sentinella zero non genera una previsione inventata',
    () async {
      final shadows = SmartBetSimulationShadowStore();
      final registration = SmartBetAnalysisRegistrationService(
        store: SmartBetAnalysisHistoryStore(),
        simulationCapture: SmartBetSimulationShadowCaptureService(
          store: shadows,
        ),
      );
      await registration.registerSelection(
        match: match(2104),
        smartBet: prediction(homeXg: 0),
        source: SmartBetAnalysisSource.analysis,
        smartBetMarket: '1',
        recordedAt: before,
      );
      expect(shadows.snapshots, isEmpty);
    },
  );

  test('P21C: primi dati persistono dopo riapertura store', () async {
    final shadows = SmartBetSimulationShadowStore();
    final registration = SmartBetAnalysisRegistrationService(
      store: SmartBetAnalysisHistoryStore(),
      simulationCapture: SmartBetSimulationShadowCaptureService(store: shadows),
    );
    await registration.registerSelection(
      match: match(2105),
      smartBet: prediction(),
      source: SmartBetAnalysisSource.analysis,
      smartBetMarket: 'X',
      recordedAt: before,
    );
    final restarted = SmartBetSimulationShadowStore();
    await restarted.initialize();
    expect(restarted.snapshots, hasLength(1));
    expect(restarted.snapshots.single.originalProbabilities['X'], 0.27);
    expect(restarted.snapshots.single.fixtureId, 2105);
  });

  test('P21C: scritture concorrenti non duplicano la partita', () async {
    final shadows = SmartBetSimulationShadowStore();
    final registration = SmartBetAnalysisRegistrationService(
      store: SmartBetAnalysisHistoryStore(),
      simulationCapture: SmartBetSimulationShadowCaptureService(store: shadows),
    );
    // Gli snapshot della stessa partita non sono mai riscritti.
    await registration.registerSelection(
      match: match(2106),
      smartBet: prediction(),
      source: SmartBetAnalysisSource.analysis,
      smartBetMarket: 'X',
      recordedAt: before,
    );
    final snapshot = shadows.snapshots.single;
    final results = await Future.wait([
      shadows.saveFirst(snapshot),
      shadows.saveFirst(snapshot),
    ]);
    expect(results, [false, false]);
    expect(shadows.snapshots, hasLength(1));
  });
}
