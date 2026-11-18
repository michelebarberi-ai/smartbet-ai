import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/diego_ai_market_probability_service.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_three_engine_benchmark_store.dart';
import 'package:smartbet_ai_new/services/goalvdline_three_engine_paired_comparison_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_three_engine_paired_comparison_panel.dart';

class _Diego implements DiegoAiAnalysis {
  final int fixtureId;
  @override
  MatchModel get match => _match(fixtureId);
  @override
  final double expectedHomeGoals = 1.55;
  @override
  final double expectedAwayGoals = 0.95;
  @override
  final int dataConfidence = 75;
  @override
  final List<DiegoAiMarketProbability> markets;

  const _Diego({
    this.fixtureId = 981,
    this.markets = const [
      DiegoAiMarketProbability(market: '1', probability: 0.61),
      DiegoAiMarketProbability(market: 'X', probability: 0.25),
      DiegoAiMarketProbability(market: '2', probability: 0.14),
      DiegoAiMarketProbability(market: 'GOAL', probability: 0.59),
      DiegoAiMarketProbability(market: 'NO GOAL', probability: 0.41),
      DiegoAiMarketProbability(market: 'OVER 1.5', probability: 0.72),
      DiegoAiMarketProbability(market: 'UNDER 1.5', probability: 0.28),
      DiegoAiMarketProbability(market: 'OVER 2.5', probability: 0.49),
      DiegoAiMarketProbability(market: 'UNDER 2.5', probability: 0.51),
    ],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

MatchModel _match(int id) => MatchModel(
    fixtureId: id,
    homeTeamId: 1,
    awayTeamId: 2,
    homeTeam: 'Juventus',
    awayTeam: 'Parma',
    league: 'Serie A',
    leagueId: 135,
    country: 'Italy',
    countryCode: 'IT',
    date: DateTime.utc(2026, 12, 15, 20, 45).toIso8601String(),
    leagueType: 'domestic',
    isEuropeanCup: false,
    isFriendly: false,
    isNational: false,
    aiWeight: 0.7,
    smartScore: 0,
    homeWin: 0,
    draw: 0,
    awayWin: 0,
    valueBet: '',
    odd: 0,
  );

class _MismatchDiego extends _Diego {
  final MatchModel otherMatch;
  const _MismatchDiego(this.otherMatch);
  @override
  MatchModel get match => otherMatch;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final kickoff = DateTime.utc(2026, 12, 15, 20, 45);
  final recorded = kickoff.subtract(const Duration(days: 2));
  final scoredAt = kickoff.add(const Duration(hours: 5));
  final asOf = kickoff.add(const Duration(days: 1));

  MatchModel match(int id) => _match(id);

  AnalysisResult smart({
    int score = 75,
    int over25 = 60,
    int goal = 55,
  }) => AnalysisResult(
    smartScore: score,
    dataConfidence: 78,
    homeProbability: 65,
    drawProbability: 22,
    awayProbability: 13,
    over15Probability: 75,
    under15Probability: 25,
    over25Probability: over25,
    under25Probability: 40,
    goalProbability: goal,
    noGoalProbability: 45,
    expectedHomeGoals: 1.8,
    expectedAwayGoals: 1.05,
    prediction: '1',
    valueBet: '',
    risk: 'Medio',
    explanation: 'Test benchmark',
  );

  Future<bool> capture(
    GoalVdLineThreeEngineBenchmarkStore store, {
    int fixture = 981,
    AnalysisResult? result,
    DiegoAiAnalysis? diego,
    bool missingDiego = false,
    DateTime? seen,
  }) => GoalVdLineThreeEngineBenchmarkCaptureService(store: store).capture(
    match: match(fixture),
    smartBet: result ?? smart(),
    diego: missingDiego ? null : diego ?? _Diego(fixtureId: fixture),
    recordedAt: seen ?? recorded,
  );

  test('congela mercati fissi e probabilita originali, separato dallo storico', () async {
    final benchmarks = GoalVdLineThreeEngineBenchmarkStore();
    final history = SmartBetAnalysisHistoryStore();
    await history.initialize();

    expect(await capture(benchmarks), isTrue);
    final first = benchmarks.snapshots.single;
    expect(first.fixtureId, 981);
    expect(first.firstSeenAt, recorded);
    expect(first.thirdInputSource, 'SmartBet AI');
    expect(first.thirdModelVersion, isNotEmpty);
    expect(first.markets.map((m) => m.market).toSet(),
      containsAll(['1', 'X', '2', 'GOAL', 'OVER 2.5']));
    expect(first.markets.firstWhere((m) => m.market == '1').smartBet, 0.65);
    expect(first.markets.firstWhere((m) => m.market == '1').diego, 0.61);

    expect(await capture(benchmarks, result: smart(over25: 99, goal: 99),
      seen: recorded.add(const Duration(hours: 1))), isFalse);
    expect(benchmarks.snapshots.single.toJson(), first.toJson());
    expect(history.records, isEmpty, reason: 'No MEI/coupon/learning contamination');

    final reloaded = GoalVdLineThreeEngineBenchmarkStore();
    await reloaded.initialize();
    expect(reloaded.snapshots, hasLength(1));
    expect(reloaded.snapshots.single.toJson(), first.toJson());
  });

  test('join agli esiti reali gia risolti crea terne per ogni mercato', () async {
    final store = GoalVdLineThreeEngineBenchmarkStore();
    expect(await capture(store, fixture: 982), isTrue);
    final history = SmartBetAnalysisHistoryStore();
    await history.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 982,
      homeTeam: 'Juventus',
      awayTeam: 'Parma',
      league: 'Serie A',
      country: 'Italy',
      matchDate: kickoff,
      market: '1',
      probability: 0.65,
      recordedAt: recorded,
    );
    expect(store.verifiedPairedRecords(
      resultHistory: history.records,
      asOf: asOf,
    ), isEmpty, reason: 'No outcome known before settlement');

    await history.registerActualResult(
      fixtureId: 982,
      homeGoals: 2,
      awayGoals: 1,
      updatedAt: scoredAt,
    );

    final records = store.verifiedPairedRecords(
      resultHistory: history.records,
      asOf: asOf,
    );
    expect(records, hasLength(store.snapshots.single.markets.length * 3));
    expect(records.every((r) => r.prospectiveEligible &&
        r.outcomeKnownBy == scoredAt &&
        r.firstSeenAt == recorded), isTrue);
    final report = const GoalVdLineThreeEnginePairedComparisonService()
        .evaluate(records: records, asOf: asOf);
    expect(report.pairedFixtureMarkets,
      store.snapshots.single.markets.length);
    expect(report.segments, isNotEmpty);
    expect(report.segments.every((s) =>
      s.fixtureCount == 1 && !s.canChangePredictions), isTrue);
    expect(history.records, hasLength(1), reason: 'Read-only join');
    final goal = report.segments.singleWhere((s) => s.market == 'GOAL');
    expect(goal.forEngine(SmartBetAnalysisEngine.smartBet).correct, 1);
    expect(goal.forEngine(SmartBetAnalysisEngine.diego).correct, 1);
    expect(goal.forEngine(SmartBetAnalysisEngine.thirdBrain).correct, 1);
    expect(goal.forEngine(SmartBetAnalysisEngine.smartBet).brierScore,
      isNot(goal.forEngine(SmartBetAnalysisEngine.diego).brierScore));
  });

  test('conoscenza futura non entra in un report precedente', () async {
    final store = GoalVdLineThreeEngineBenchmarkStore();
    await capture(store);
    final history = SmartBetAnalysisHistoryStore();
    await history.registerAnalysis(
      engine: SmartBetAnalysisEngine.diego,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 981,
      homeTeam: 'Juventus',
      awayTeam: 'Parma',
      league: 'Serie A',
      country: 'Italy',
      matchDate: kickoff,
      market: '1',
      probability: 0.6,
      recordedAt: recorded,
    );
    await history.registerActualResult(
      fixtureId: 981, homeGoals: 1, awayGoals: 0,
      updatedAt: scoredAt,
    );
    expect(store.verifiedPairedRecords(
      resultHistory: history.records,
      asOf: kickoff.add(const Duration(hours: 2)),
    ), isEmpty);
    expect(store.verifiedPairedRecords(
      resultHistory: history.records,
      asOf: asOf,
    ), isNotEmpty);
  });

  test('nessun benchmark senza terzo, Diego, market probability o 2m lead', () async {
    final store = GoalVdLineThreeEngineBenchmarkStore();
    expect(await capture(store, missingDiego: true), isFalse);
    expect(await capture(store, result: smart(score: 0)), isFalse);
    expect(await capture(store,
      seen: kickoff.subtract(const Duration(minutes: 1))), isFalse);
    expect(await capture(store, diego: const _Diego(markets: [])), isFalse);
    expect(store.snapshots, isEmpty);
  });

  test('scarta Diego su fixture differente e kickoff disallineato', () async {
    final store = GoalVdLineThreeEngineBenchmarkStore();
    expect(await capture(store,
      diego: const _Diego(fixtureId: 999)), isFalse);
    expect(store.snapshots, isEmpty);
    // Fixture concordante ma stagione, kickoff o date diverse sono
    // comunque escluse dal confronto prospettico.
    final altered = _match(981);
    final wrongTime = MatchModel(
      fixtureId: 981,
      homeTeamId: altered.homeTeamId,
      awayTeamId: altered.awayTeamId,
      homeTeam: altered.homeTeam,
      awayTeam: altered.awayTeam,
      league: altered.league,
      leagueId: altered.leagueId,
      country: altered.country,
      countryCode: altered.countryCode,
      date: '2026-12-16T20:45:00Z',
      leagueType: altered.leagueType,
      isEuropeanCup: altered.isEuropeanCup,
      isFriendly: altered.isFriendly,
      isNational: altered.isNational,
      aiWeight: altered.aiWeight,
      smartScore: altered.smartScore,
      homeWin: altered.homeWin,
      draw: altered.draw,
      awayWin: altered.awayWin,
      valueBet: altered.valueBet,
      odd: altered.odd,
    );
    final stale = _MismatchDiego(wrongTime);
    expect(await capture(store, diego: stale), isFalse);
    expect(store.snapshots, isEmpty);
  });

  test('non usa uno score con stato incompatibile nel confronto reale', () async {
    final store = GoalVdLineThreeEngineBenchmarkStore();
    expect(await capture(store, fixture: 995), isTrue);
    final badRecord = SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 995,
      homeTeam: 'Juventus',
      awayTeam: 'Parma',
      league: 'Serie A',
      country: 'Italy',
      matchDate: kickoff,
      market: '1',
      probability: 0.65,
      smartScore: null,
      confidence: null,
      classification: null,
      qualified: true,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 3,
      actualAwayGoals: 1,
      firstSeenAt: recorded,
      lastSeenAt: scoredAt,
      resolvedAt: scoredAt,
    );
    expect(store.verifiedPairedRecords(
      resultHistory: [badRecord], asOf: asOf,
    ), isEmpty, reason: '3-1 significa vittoria casa, non esito errato di 1');
  });

  test('non riempie percentuali mancanti con zero o quote fittizie', () async {
    final store = GoalVdLineThreeEngineBenchmarkStore();
    expect(await capture(store, result: smart(goal: 0, over25: 0)), isTrue);
    final markets = store.snapshots.single.markets.map((m) => m.market).toSet();
    expect(markets, isNot(contains('GOAL')));
    expect(markets, isNot(contains('OVER 2.5')));
    expect(markets, contains('1'));
  });

  testWidgets('pannello benchmark visibile anche senza risultati reali',
    (tester) async {
    final empty = const GoalVdLineThreeEnginePairedComparisonService()
        .evaluate(records: [], asOf: asOf);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: GoalVdLineThreeEnginePairedComparisonPanel(
          report: empty,
          fixedBenchmark: true,
          frozenFixtures: 2,
        ),
      ),
    )));
    expect(find.text('Mercati fissi dei tre motori · SHADOW'), findsOneWidget);
    expect(find.textContaining('2 partite congelate'), findsOneWidget);
    expect(find.byKey(const Key('three-engine-fixed-benchmark-panel')),
      findsOneWidget);
  });
}
