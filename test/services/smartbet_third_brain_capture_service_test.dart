import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_third_brain_capture_service.dart';
import 'package:smartbet_ai_new/services/smartbet_market_ease_index_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final first = DateTime.utc(2026, 11, 20, 10);

  MatchModel match({int id = 200, String date = '2026-11-21T20:00:00Z'}) =>
      MatchModel(
        fixtureId: id,
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
        aiWeight: 0.7,
        smartScore: 0,
        homeWin: 0,
        draw: 0,
        awayWin: 0,
        valueBet: '',
        odd: 0,
      );

  AnalysisResult analysis({double home = 1.7, double away = 1.1}) =>
      AnalysisResult(
        smartScore: 82,
        homeProbability: 55,
        drawProbability: 25,
        awayProbability: 20,
        expectedHomeGoals: home,
        expectedAwayGoals: away,
        dataConfidence: 78,
        prediction: '1',
        valueBet: '',
        risk: '',
        explanation: 'Test',
      );

  test('B66: captures seven distinct, unquoted, prospective markets', () async {
    final store = SmartBetAnalysisHistoryStore();
    final service = SmartBetThirdBrainCaptureService(store: store);
    final result = await service.capture(
      match: match(),
      smartBet: analysis(),
      source: SmartBetAnalysisSource.analysis,
      recordedAt: first,
    );
    expect(result, hasLength(7));
    expect(result.map((r) => r.market).toSet(), hasLength(7));
    expect(store.records, hasLength(7));
    expect(result.every((r) =>
        r.engine == SmartBetAnalysisEngine.simulator &&
        r.prospectiveEligible &&
        r.status == SmartBetAnalysisStatus.pending &&
        r.quotedOdd == null &&
        r.classification == 'SIMULATOR_XG_FROM_SMARTBET' &&
        r.probability != null &&
        r.probability! > 0 && r.probability! < 1), isTrue);
  });

  test('B66: first forecast immutable across screens and later xG changes',
      () async {
    final store = SmartBetAnalysisHistoryStore();
    final service = SmartBetThirdBrainCaptureService(store: store);
    final original = await service.capture(
      match: match(),
      smartBet: analysis(),
      source: SmartBetAnalysisSource.analysis,
      recordedAt: first,
    );
    final snapshot = {for (final r in original) r.market: r.probability};
    final later = await service.capture(
      match: match(),
      smartBet: analysis(home: 0.8, away: 2.1),
      source: SmartBetAnalysisSource.aiCoupon,
      recordedAt: first.add(const Duration(hours: 3)),
    );
    expect(later, hasLength(7));
    expect(store.records, hasLength(7));
    for (final r in later) {
      expect(r.probability, snapshot[r.market]);
      expect(r.firstSeenAt, first);
      expect(r.sources, contains(SmartBetAnalysisSource.analysis));
      expect(r.sources, contains(SmartBetAnalysisSource.aiCoupon));
    }
  });

  test('B66: new predictions after kickoff are not fabricated', () async {
    final store = SmartBetAnalysisHistoryStore();
    final result = await SmartBetThirdBrainCaptureService(store: store).capture(
      match: match(date: '2026-11-19T10:00:00Z'),
      smartBet: analysis(),
      source: SmartBetAnalysisSource.combinations,
      recordedAt: first,
    );
    expect(result, isEmpty);
    expect(store.records, isEmpty);
  });

  test('B66: cannot simulate missing or invalid xG', () async {
    final store = SmartBetAnalysisHistoryStore();
    final service = SmartBetThirdBrainCaptureService(store: store);
    final invalid = await service.capture(
      match: match(),
      smartBet: analysis(home: 0, away: 0),
      source: SmartBetAnalysisSource.analysis,
      recordedAt: first,
    );
    expect(invalid, isEmpty);
    expect(store.records, isEmpty);
  });

  test('B66: official final score resolves simulator markets via same engine',
      () async {
    final store = SmartBetAnalysisHistoryStore();
    await SmartBetThirdBrainCaptureService(store: store).capture(
      match: match(),
      smartBet: analysis(),
      source: SmartBetAnalysisSource.analysis,
      recordedAt: first,
    );
    final resolved = await store.registerActualResult(
      fixtureId: 200,
      homeGoals: 2,
      awayGoals: 1,
      updatedAt: DateTime.utc(2026, 11, 22),
    );
    expect(resolved, 7);
    expect(store.records.where((r) =>
        r.status == SmartBetAnalysisStatus.pending), isEmpty);
    expect(store.records.firstWhere((r) => r.market == 'GOAL').status,
        SmartBetAnalysisStatus.correct);
    expect(store.records.firstWhere((r) => r.market == 'X').status,
        SmartBetAnalysisStatus.wrong);
    final report = const SmartBetMarketEaseIndexService().evaluate(
      records: store.records,
      asOf: DateTime.utc(2026, 11, 23),
    );
    expect(report.entries, hasLength(7));
    expect(report.entries.every((e) =>
        e.evidence.engine == SmartBetAnalysisEngine.simulator &&
        e.score == null), isTrue);
  });

  test('B66: snapshots survive reinitialization using the same storage', () async {
    final firstStore = SmartBetAnalysisHistoryStore();
    await SmartBetThirdBrainCaptureService(store: firstStore).capture(
      match: match(),
      smartBet: analysis(),
      source: SmartBetAnalysisSource.analysis,
      recordedAt: first,
    );
    final reopened = SmartBetAnalysisHistoryStore();
    await reopened.initialize();
    expect(reopened.records.where((r) =>
        r.engine == SmartBetAnalysisEngine.simulator), hasLength(7));
  });
}
