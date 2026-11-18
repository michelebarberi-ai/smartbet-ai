import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_third_brain_history_capture_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

class _FakeDiego implements DiegoAiAnalysis {
  @override final double expectedHomeGoals;
  @override final double expectedAwayGoals;
  @override final int dataConfidence;
  const _FakeDiego(this.expectedHomeGoals, this.expectedAwayGoals, this.dataConfidence);
  @override dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final kickoff = DateTime.utc(2026, 12, 15, 20, 45);
  final recorded = kickoff.subtract(const Duration(days: 2));

  MatchModel match(int fixture) => MatchModel(
    fixtureId: fixture,
    homeTeamId: 1,
    awayTeamId: 2,
    homeTeam: 'Juventus',
    awayTeam: 'Parma',
    league: 'Serie A',
    leagueId: 135,
    country: 'Italy',
    countryCode: 'IT',
    date: kickoff.toIso8601String(),
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
    odd: 0,
  );

  AnalysisResult smart({
    int score = 75,
    int quality = 75,
    double home = 2.1,
    double away = 0.9,
  }) => AnalysisResult(
    smartScore: score,
    dataConfidence: quality,
    homeProbability: 70,
    drawProbability: 20,
    awayProbability: 10,
    prediction: '1',
    valueBet: '',
    risk: 'Medio',
    explanation: 'Test SmartBet',
    expectedHomeGoals: home,
    expectedAwayGoals: away,
  );

  test('terzo cervello: cinque mercati predefiniti, input SmartBet tracciato', () async {
    final store = SmartBetAnalysisHistoryStore();
    final captured = await GoalVdLineThirdBrainHistoryCaptureService(store: store)
        .capture(
      match: match(1001), smartBet: smart(),
      source: SmartBetAnalysisSource.analysis, recordedAt: recorded,
    );

    expect(captured, hasLength(5));
    expect(captured.every((r) =>
        r.engine == SmartBetAnalysisEngine.thirdBrain &&
        r.prospectiveEligible &&
        r.status == SmartBetAnalysisStatus.pending &&
        r.quotedOdd == null &&
        r.modelVersion!.contains('bivariate-poisson') &&
        r.inputSource == 'SmartBet AI' &&
        r.probability != null &&
        r.probability! >= 0 &&
        r.probability! <= 1), isTrue);
    expect(captured.map((r) => r.market).toSet().length, 5);
    expect(store.records, hasLength(5));

    // Snapshot attraversa JSON e un nuovo storage senza perdere la provenienza.
    final reloaded = SmartBetAnalysisHistoryStore();
    await reloaded.initialize();
    expect(reloaded.records, hasLength(5));
    expect(reloaded.records.first.inputSource, 'SmartBet AI');
    expect(reloaded.records.first.modelVersion, captured.first.modelVersion);
  });

  test('prima previsione immutabile anche dopo una nuova analisi diversa', () async {
    final store = SmartBetAnalysisHistoryStore();
    final capture = GoalVdLineThirdBrainHistoryCaptureService(store: store);
    final first = await capture.capture(
      match: match(1002), smartBet: smart(),
      source: SmartBetAnalysisSource.analysis, recordedAt: recorded,
    );
    final repeated = await capture.capture(
      match: match(1002), smartBet: smart(home: 4.2, away: 0.5),
      source: SmartBetAnalysisSource.combinations,
      recordedAt: recorded.add(const Duration(hours: 1)),
    );
    expect(repeated, hasLength(5));
    expect(store.records, hasLength(5));
    for (final original in first) {
      final saved = store.records.singleWhere((r) => r.market == original.market);
      expect(saved.probability, original.probability);
      expect(saved.firstSeenAt, recorded);
      expect(saved.sources, containsAll([
        SmartBetAnalysisSource.analysis,
        SmartBetAnalysisSource.combinations,
      ]));
    }
  });

  test('esito reale liquida record del terzo senza influenzare altri motori', () async {
    final store = SmartBetAnalysisHistoryStore();
    await GoalVdLineThirdBrainHistoryCaptureService(store: store).capture(
      match: match(1003), smartBet: smart(),
      source: SmartBetAnalysisSource.analysis, recordedAt: recorded,
    );
    expect(await store.registerActualResult(
      fixtureId: 1003, homeGoals: 3, awayGoals: 1,
      updatedAt: kickoff.add(const Duration(hours: 4)),
    ), 5);
    expect(store.records.every((r) =>
      r.status == SmartBetAnalysisStatus.correct ||
      r.status == SmartBetAnalysisStatus.wrong), isTrue);
    expect(store.records.every((r) =>
      r.firstSeenAt == recorded &&
      r.outcomeKnownBy!.isAfter(kickoff)), isTrue);
  });

  test('quando usa xG Diego, non li attribuisce a SmartBet', () async {
    final store = SmartBetAnalysisHistoryStore();
    final captured = await GoalVdLineThirdBrainHistoryCaptureService(store: store)
        .capture(
      match: match(1004),
      smartBet: smart(score: 0, home: 0, away: 0),
      diego: const _FakeDiego(1.35, 1.7, 65),
      source: SmartBetAnalysisSource.analysis, recordedAt: recorded,
    );
    expect(captured, hasLength(5));
    expect(captured.every((r) => r.inputSource == 'Diego AI'), isTrue);
  });

  test('niente storico retrospettivo o con dati insufficienti', () async {
    final store = SmartBetAnalysisHistoryStore();
    final service = GoalVdLineThirdBrainHistoryCaptureService(store: store);
    expect(await service.capture(
      match: match(1005), smartBet: smart(),
      source: SmartBetAnalysisSource.analysis,
      recordedAt: kickoff.add(const Duration(minutes: 1)),
    ), isEmpty);
    expect(await service.capture(
      match: match(1006), smartBet: smart(quality: 0),
      source: SmartBetAnalysisSource.analysis, recordedAt: recorded,
    ), isEmpty);
    expect(await service.capture(
      match: match(1007), smartBet: smart(score: 0, home: 0, away: 0),
      source: SmartBetAnalysisSource.analysis, recordedAt: recorded,
    ), isEmpty);
    expect(store.records, isEmpty);
  });
}
