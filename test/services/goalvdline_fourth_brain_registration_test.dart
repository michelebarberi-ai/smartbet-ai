import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/dual_engine_analysis_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_central_learning_outbox.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_registration_service.dart';

class _NativeDiego implements DiegoAiAnalysis {
  @override
  final MatchModel match;
  const _NativeDiego(this.match);
  @override
  double get homeProbability => 0.5;
  @override
  double get drawProbability => 0.26;
  @override
  double get awayProbability => 0.24;
  @override
  double get goalProbability => 0.64;
  @override
  double get noGoalProbability => 0.36;
  @override
  double get over25Probability => 0.56;
  @override
  double get under25Probability => 0.44;
  @override
  double get expectedHomeGoals => 1.6;
  @override
  double get expectedAwayGoals => 1.0;
  @override
  int get dataConfidence => 75;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

MatchModel match() => MatchModel(
  fixtureId: 9191, homeTeamId: 1, awayTeamId: 2,
  homeTeam: 'Casa', awayTeam: 'Ospite', league: 'Serie A',
  leagueId: 135, country: 'Italy', countryCode: 'IT',
  date: '2026-11-20T20:00:00Z', leagueType: 'domestic',
  isEuropeanCup: false, isFriendly: false, isNational: false,
  aiWeight: 0.8, smartScore: 0,
  homeWin: 0, draw: 0, awayWin: 0, valueBet: '', odd: 0,
);

const smart = AnalysisResult(
  smartScore: 82,
  homeProbability: 54, drawProbability: 24, awayProbability: 22,
  goalProbability: 62, noGoalProbability: 38,
  over25Probability: 57, under25Probability: 43,
  expectedHomeGoals: 1.7, expectedAwayGoals: 1.2,
  dataConfidence: 78, prediction: '1',
  valueBet: '', risk: '', explanation: 'Storico originale',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('B67: registration captures fourth AI even without bookmaker pick',
      () async {
    final fixture = match();
    final store = SmartBetAnalysisHistoryStore();
    final outbox = GoalVdLineCentralLearningOutbox(
      preferences: await SharedPreferences.getInstance(),
      clock: () => DateTime.utc(2026, 11, 18, 10),
    );
    final service = SmartBetAnalysisRegistrationService(
      store: store, centralOutbox: outbox,
    );
    final dual = DualEngineAnalysis(
      smartBet: smart,
      diego: _NativeDiego(fixture),
      comparison: const DualEngineComparison(
        status: DualEngineAgreement.unavailable,
        smartBetMarket: 'N/D',
        diegoMarket: 'N/D',
      ),
    );
    await service.registerSelection(
      match: fixture, smartBet: smart,
      source: SmartBetAnalysisSource.analysis, dualAnalysis: dual,
      recordedAt: DateTime.utc(2026, 11, 18, 10),
    );
    expect(store.records.where((r) =>
        r.engine == SmartBetAnalysisEngine.metaAi), hasLength(7));
    expect(store.records.where((r) =>
        r.engine == SmartBetAnalysisEngine.simulator), hasLength(7));
    expect(store.records.where((r) =>
        r.engine == SmartBetAnalysisEngine.diego), isEmpty);
    expect(store.records.every((r) => r.quotedOdd == null), isTrue);

    // Meta AI must NEVER be serialized for the existing two/three-engine
    // Neon API while the server schema only knows SmartBet/Diego/Simulator.
    final meta = store.records.firstWhere(
      (r) => r.engine == SmartBetAnalysisEngine.metaAi,
    );
    await outbox.setConsent(true);
    expect(await outbox.captureIfEligible(meta), isFalse);
    expect(outbox.pendingCount, 0);
  });
}
