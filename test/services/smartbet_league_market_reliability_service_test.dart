import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_league_market_reliability_service.dart';

void main() {
  const service = SmartBetLeagueMarketReliabilityService();
  final cutoff = DateTime.utc(2026, 11, 13);

  SmartBetAnalysisRecord record({
    required int fixture,
    String league = 'Serie A',
    String country = 'Italia',
    String market = 'GOAL',
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
    double? probability = 0.70,
    DateTime? kickoff,
    DateTime? firstSeenAt,
    DateTime? knownAt,
    bool prospective = true,
    double? odd,
  }) {
    final start = kickoff ?? DateTime.utc(2026, 7, 1).add(Duration(days: fixture));
    final first = firstSeenAt ?? start.subtract(const Duration(hours: 6));
    final resolved = knownAt ?? start.add(const Duration(hours: 3));
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixture,
      homeTeam: 'A',
      awayTeam: 'B',
      league: league,
      country: country,
      matchDate: start,
      market: market,
      probability: probability,
      smartScore: 75,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: status,
      actualHomeGoals: status == SmartBetAnalysisStatus.pending ? null : 2,
      actualAwayGoals: status == SmartBetAnalysisStatus.pending ? null : 1,
      firstSeenAt: first,
      lastSeenAt: resolved,
      resolvedAt: status == SmartBetAnalysisStatus.pending ? null : resolved,
      quotedOdd: odd,
    );
  }

  test('P21W: real sample: correctness, Brier, calibrated gap and CI', () {
    final records = [
      for (var i = 0; i < 50; i++)
        record(fixture: i + 1,
          status: i < 35
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong),
    ];
    final report = service.evaluate(records: records, asOf: cutoff);
    final segment = report.find(
      engine: SmartBetAnalysisEngine.smartBet,
      country: 'Italia', league: 'Serie A', market: 'goal',
    )!;
    expect(report.uniqueEligibleRecords, 50);
    expect(segment.sampleSize, 50);
    expect(segment.correct, 35);
    expect(segment.wrong, 15);
    expect(segment.distinctMatchDays, 50);
    expect(segment.observedAccuracyPercent, 70);
    expect(segment.averagePredictedPercent, closeTo(70, 0.000001));
    expect(segment.calibrationGapPoints, closeTo(0, 0.000001));
    expect(segment.brierScore, closeTo(0.21, 0.000001));
    expect(segment.wilsonLower95Percent, lessThan(70));
    expect(segment.wilsonUpper95Percent, greaterThan(70));
    expect(segment.evidenceLevel, SmartBetLeagueMarketEvidenceLevel.exploratory);
    expect(segment.readyForShadowResearch, false);
  });

  test('P21W: sufficient data is NOT a permission to affect live picks', () {
    final records = [
      for (var i = 0; i < 210; i++)
        record(fixture: 500 + i,
          kickoff: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
          status: i < 170
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong),
    ];
    final report = service.evaluate(records: records, asOf: cutoff);
    final segment = report.segments.single;
    expect(segment.sampleSize, 210);
    expect(segment.evidenceLevel,
      SmartBetLeagueMarketEvidenceLevel.strongShadowCandidate);
    expect(segment.readyForShadowResearch, true);
    // It is report-only: there is no method that edits a forecast or a coupon.
  });

  test('P21W: exclude hindsight, unverified and unavailable outcomes', () {
    final kickoff = DateTime.utc(2026, 10, 30, 18);
    final report = service.evaluate(records: [
      record(fixture: 1, kickoff: kickoff, firstSeenAt: kickoff.add(const Duration(seconds: 1))),
      record(fixture: 2, kickoff: kickoff, knownAt: cutoff.add(const Duration(days: 1))),
      record(fixture: 3, kickoff: kickoff, prospective: false),
      record(fixture: 4, kickoff: kickoff, status: SmartBetAnalysisStatus.pending),
      record(fixture: 5, kickoff: kickoff, knownAt: kickoff.subtract(const Duration(seconds: 1))),
      record(fixture: 6, kickoff: kickoff, probability: double.nan),
      record(fixture: 7, kickoff: kickoff, probability: 0.75),
    ], asOf: cutoff);
    expect(report.uniqueEligibleRecords, 1);
    expect(report.skippedUnsafeRecords, 6);
    expect(report.segments.single.sampleSize, 1);
    expect(report.segments.single.evidenceLevel, SmartBetLeagueMarketEvidenceLevel.insufficient);
  });

  test('P21W: one fixture + market contributes once; conflict is excluded', () {
    final first = record(fixture: 1, market: ' Goal ', odd: 1.20);
    final duplicate = record(fixture: 1, market: 'GOAL', odd: 9.0);
    final conflicting = record(fixture: 2, status: SmartBetAnalysisStatus.correct);
    final conflictingOutcome = record(fixture: 2, status: SmartBetAnalysisStatus.wrong);
    final otherMarket = record(fixture: 3, market: 'OVER 2.5');
    final report = service.evaluate(records: [
      first, duplicate, conflicting, conflictingOutcome, otherMarket,
    ], asOf: cutoff);
    expect(report.duplicateRecords, 1);
    expect(report.conflictingFixtureMarkets, 1);
    expect(report.uniqueEligibleRecords, 2);
    expect(report.find(engine: SmartBetAnalysisEngine.smartBet,
      country: 'Italia', league: 'Serie A', market: 'GOAL')!.sampleSize, 1);
  });

  test('P21W: reports stay separated by engine, country, league and market', () {
    final report = service.evaluate(records: [
      record(fixture: 1, market: 'GOAL'),
      record(fixture: 2, market: 'NO GOAL'),
      record(fixture: 3, engine: SmartBetAnalysisEngine.diego),
      record(fixture: 4, country: 'England', league: 'Serie A'),
      record(fixture: 5, country: 'Italia', league: 'Serie B'),
    ], asOf: cutoff);
    expect(report.segments.length, 5);
  });

  test('P21W: no data means unknown, not zero reliability', () {
    final report = service.evaluate(records: [], asOf: cutoff);
    expect(report.segments, isEmpty);
    expect(report.find(engine: SmartBetAnalysisEngine.smartBet,
      country: 'Italia', league: 'Serie A', market: 'GOAL'), isNull);
  });

  test('P21W: 95% Wilson interval stays within bounds for extremes', () {
    final allCorrect = service.evaluate(records: [
      for (var i = 0; i < 10; i++) record(fixture: i + 1),
    ], asOf: cutoff).segments.single;
    final noneCorrect = service.evaluate(records: [
      for (var i = 0; i < 10; i++)
        record(fixture: i + 1, status: SmartBetAnalysisStatus.wrong),
    ], asOf: cutoff).segments.single;
    expect(allCorrect.wilsonUpper95Percent, lessThanOrEqualTo(100));
    expect(allCorrect.wilsonLower95Percent, greaterThan(0));
    expect(noneCorrect.wilsonLower95Percent, greaterThanOrEqualTo(0));
    expect(noneCorrect.wilsonUpper95Percent, lessThan(100));
  });
}
