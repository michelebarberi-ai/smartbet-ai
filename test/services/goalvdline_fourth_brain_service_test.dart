import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_fourth_brain_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

const brain = GoalVdLineFourthBrainService();
final now = DateTime.utc(2026, 11, 18, 13);
final kickoff = DateTime.utc(2026, 11, 20, 20);

class _Diego implements DiegoAiAnalysis {
  @override
  final MatchModel match;

  const _Diego(this.match);

  @override
  double get homeProbability => 0.50;
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

MatchModel fixture({int id = 200, String date = '2026-11-20T20:00:00Z'}) =>
    MatchModel(
      fixtureId: id, homeTeamId: 1, awayTeamId: 2,
      homeTeam: 'Casa', awayTeam: 'Ospite',
      league: 'Serie A', leagueId: 135,
      country: 'Italy', countryCode: 'IT',
      date: date, leagueType: 'domestic',
      isEuropeanCup: false, isFriendly: false, isNational: false,
      aiWeight: 0.7, smartScore: 0,
      homeWin: 0, draw: 0, awayWin: 0, valueBet: '', odd: 0,
    );

AnalysisResult smart({
  int score = 82, int home = 54, int draw = 24, int away = 22,
}) => AnalysisResult(
  smartScore: score, homeProbability: home,
  drawProbability: draw, awayProbability: away,
  goalProbability: 62, noGoalProbability: 38,
  over25Probability: 57, under25Probability: 43,
  expectedHomeGoals: 1.7, expectedAwayGoals: 1.2,
  dataConfidence: 78,
  prediction: '1', valueBet: '', risk: '', explanation: 'Prepartita',
);

GoalVdLineFourthBrainReport evaluate({
  Map<String, double> smartBet = const {'GOAL': 0.70},
  Map<String, double> diego = const {'GOAL': 0.60},
  Map<String, double> simulator = const {'GOAL': 0.80},
  String? origin = 'smartBet',
  Iterable<SmartBetAnalysisRecord> historicalRecords = const [],
  DateTime? at,
}) => brain.evaluate(
  fixtureId: 200, country: 'Italy', league: 'Serie A',
  kickoffAt: kickoff, asOf: at ?? now,
  smartBet: smartBet, diego: diego, simulator: simulator,
  simulatorInputSource: origin,
  historicalRecords: historicalRecords,
);

SmartBetAnalysisRecord historyRecord({
  required int fixtureId,
  required SmartBetAnalysisEngine engine,
  required bool success,
  required DateTime matchDate,
  double probability = 0.70,
  DateTime? knownAt,
}) {
  final first = matchDate.subtract(const Duration(days: 1));
  final homeGoals = success ? 1 : 2;
  final awayGoals = success ? 1 : 0;
  return SmartBetAnalysisRecord(
    engine: engine, fixtureId: fixtureId,
    homeTeam: 'A', awayTeam: 'B',
    country: 'Italy', league: 'Serie A', matchDate: matchDate,
    market: 'GOAL', probability: probability, smartScore: null,
    confidence: null, classification: null,
    qualified: true, sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: true,
    status: success ? SmartBetAnalysisStatus.correct
        : SmartBetAnalysisStatus.wrong,
    actualHomeGoals: homeGoals, actualAwayGoals: awayGoals,
    firstSeenAt: first, lastSeenAt: first,
    resolvedAt: knownAt ?? matchDate.add(const Duration(hours: 3)),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('B67: combines only identical full-time markets and never enables picks', () {
    final report = evaluate();
    expect(report.forecasts, hasLength(1));
    final f = report.forecasts.single;
    expect(f.market, 'GOAL');
    expect(f.probability, closeTo(0.6625, 1e-10));
    expect(f.smartBetWeight, closeTo(0.375, 1e-10));
    expect(f.diegoWeight, closeTo(0.5, 1e-10));
    expect(f.simulatorWeight, closeTo(0.125, 1e-10));
    expect(f.evidenceQualified, isFalse);
    expect(f.allowedForLiveSelection, isFalse);
    expect(f.status, GoalVdLineFourthBrainStatus.exploratoryShadow);
  });

  test('B67: simulator shares Diego budget, not a third independent vote', () {
    final forecast = evaluate(origin: 'diego').forecasts.single;
    expect(forecast.smartBetWeight, 0.5);
    expect(forecast.diegoWeight, 0.375);
    expect(forecast.simulatorWeight, 0.125);
    expect(forecast.probability, closeTo(0.675, 1e-10));
  });

  test('B67: missing provenance excludes simulator without silently relabeling', () {
    for (final source in [null, 'unknown', 'external']) {
      final f = evaluate(origin: source).forecasts.single;
      expect(f.probability, closeTo(0.65, 1e-10));
      expect(f.simulatorWeight, 0);
      expect(f.simulatorProbability, isNull);
      expect(f.simulatorInputSource, isNull);
    }
  });

  test('B67: never invents market overlap, zero data or post-kickoff snapshots', () {
    expect(evaluate(diego: const {'X': 0.30}).forecasts, isEmpty);
    expect(evaluate(smartBet: const {}).forecasts, isEmpty);
    expect(evaluate(diego: const {'GOAL': double.nan}).forecasts, isEmpty);
    expect(evaluate(at: kickoff).forecasts, isEmpty);
    expect(evaluate(at: kickoff.add(const Duration(minutes: 1))).forecasts,
        isEmpty);
  });

  test('B67: divergent models abstain from recommendations, still audit forecast', () {
    final f = evaluate(
      smartBet: const {'GOAL': 0.82},
      diego: const {'GOAL': 0.41},
    ).forecasts.single;
    expect(f.status, GoalVdLineFourthBrainStatus.divergentShadow);
    expect(f.disagreementPoints, closeTo(41, 1e-8));
    expect(f.allowedForLiveSelection, isFalse);
  });

  test('B67: MEI weights only after 100 outcomes and 14 days for both engines', () {
    final historic = <SmartBetAnalysisRecord>[];
    for (var i = 0; i < 120; i++) {
      final kickoffOld = DateTime.utc(2026, 10, 1 + (i % 20), 20);
      historic.add(historyRecord(
        fixtureId: 1000 + i, engine: SmartBetAnalysisEngine.smartBet,
        success: i < 100, matchDate: kickoffOld, probability: 0.80,
      ));
      historic.add(historyRecord(
        fixtureId: 2000 + i, engine: SmartBetAnalysisEngine.diego,
        success: i < 70, matchDate: kickoffOld, probability: 0.65,
      ));
    }
    final forecast = evaluate(
      smartBet: const {'GOAL': 0.70},
      diego: const {'GOAL': 0.64},
      simulator: const {},
      historicalRecords: historic,
    ).forecasts.single;
    expect(forecast.evidenceQualified, isTrue);
    expect(forecast.smartBetWeight, greaterThan(0.5));
    expect(forecast.smartBetWeight, lessThanOrEqualTo(0.6));
    expect(forecast.diegoWeight, greaterThanOrEqualTo(0.4));
    expect(forecast.allowedForLiveSelection, isFalse);
  });

  test('B67: outcomes known only after prediction cannot weight meta AI', () {
    final futureKnown = <SmartBetAnalysisRecord>[];
    for (var i = 0; i < 120; i++) {
      final kickoffOld = DateTime.utc(2026, 10, 1 + (i % 20), 20);
      final after = DateTime.utc(2026, 11, 22);
      futureKnown.add(historyRecord(
        fixtureId: 3000 + i, engine: SmartBetAnalysisEngine.smartBet,
        success: true, matchDate: kickoffOld, knownAt: after,
      ));
      futureKnown.add(historyRecord(
        fixtureId: 4000 + i, engine: SmartBetAnalysisEngine.diego,
        success: false, matchDate: kickoffOld, knownAt: after,
      ));
    }
    final f = evaluate(historicalRecords: futureKnown).forecasts.single;
    expect(f.evidenceQualified, isFalse);
    expect(f.smartBetWeight, closeTo(0.375, 1e-10));
  });

  test('B67: wrong claimed outcome is excluded from dynamic evidence', () {
    final contradictory = <SmartBetAnalysisRecord>[];
    for (var i = 0; i < 120; i++) {
      final kickoffOld = DateTime.utc(2026, 10, 1 + (i % 20), 20);
      contradictory.add(historyRecord(
        fixtureId: 5000 + i, engine: SmartBetAnalysisEngine.smartBet,
        success: true, matchDate: kickoffOld,
      ));
      contradictory.add(historyRecord(
        fixtureId: 6000 + i, engine: SmartBetAnalysisEngine.diego,
        success: true, matchDate: kickoffOld,
      ).withActualResult(
        homeGoals: 2, awayGoals: 0, status: SmartBetAnalysisStatus.correct,
        updatedAt: kickoffOld.add(const Duration(hours: 3)),
      ));
    }
    final f = evaluate(historicalRecords: contradictory).forecasts.single;
    expect(f.evidenceQualified, isFalse);
  });

  test('B67: invalid source distribution does not manufacture a market', () {
    expect(GoalVdLineFourthBrainService.smartBetMarkets(
      smart(home: 40, draw: 30, away: 20),
    ), isEmpty);
    expect(GoalVdLineFourthBrainService.smartBetMarkets(
      smart(score: 0),
    ), isEmpty);
    expect(GoalVdLineFourthBrainService.smartBetMarkets(smart()), hasLength(7));
  });

  test('B67: immutable prospective meta snapshots settle on actual result', () async {
    final store = SmartBetAnalysisHistoryStore();
    final m = fixture();
    final diego = _Diego(m);
    final first = await brain.capture(
      store: store, match: m, smartBet: smart(), diego: diego,
      source: SmartBetAnalysisSource.analysis, recordedAt: now,
    );
    expect(first, hasLength(7));
    expect(first.every((r) =>
        r.engine == SmartBetAnalysisEngine.metaAi &&
        r.quotedOdd == null && r.prospectiveEligible &&
        r.classification!.startsWith('META_B67_V1_SHADOW_')), isTrue);

    final p = {for (final r in first) r.market: r.probability};
    final second = await brain.capture(
      store: store, match: m,
      smartBet: smart(home: 50, draw: 25, away: 25), diego: diego,
      source: SmartBetAnalysisSource.combinations,
      recordedAt: now.add(const Duration(hours: 1)),
    );
    expect(second, hasLength(7));
    expect(store.records, hasLength(7));
    for (final record in second) {
      expect(record.probability, p[record.market]);
      expect(record.firstSeenAt, now);
      expect(record.sources, contains(SmartBetAnalysisSource.combinations));
    }
    expect(await store.registerActualResult(
      fixtureId: m.fixtureId, homeGoals: 2, awayGoals: 1,
      updatedAt: DateTime.utc(2026, 11, 21),
    ), 7);
    final goal = store.records.firstWhere((r) => r.market == 'GOAL');
    expect(goal.status, SmartBetAnalysisStatus.correct);
    expect(goal.outcomeKnownBy, isNotNull);
  });

  test('B67: no forecast after kickoff or with no separate Diego analysis',
      () async {
    final store = SmartBetAnalysisHistoryStore();
    final m = fixture();
    expect(await brain.capture(
      store: store, match: m, smartBet: smart(), diego: null,
      source: SmartBetAnalysisSource.analysis, recordedAt: now,
    ), isEmpty);
    expect(await brain.capture(
      store: store, match: m, smartBet: smart(), diego: _Diego(m),
      source: SmartBetAnalysisSource.analysis, recordedAt: kickoff,
    ), isEmpty);
    expect(store.records, isEmpty);
  });
}
