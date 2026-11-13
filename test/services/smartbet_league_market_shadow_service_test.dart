import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_league_market_shadow_service.dart';

void main() {
  const service = SmartBetLeagueMarketShadowService();
  final cutoff = DateTime.utc(2026, 11, 13);

  SmartBetAnalysisRecord record({
    required int fixture,
    DateTime? kickoff,
    DateTime? firstSeen,
    DateTime? known,
    String country = 'Italia',
    String league = 'Serie A',
    String market = 'GOAL',
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    double probability = 0.60,
    SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
    bool prospective = true,
    double? odd,
  }) {
    final match = kickoff ?? DateTime.utc(2026, 1, 1).add(Duration(days: fixture));
    final created = firstSeen ?? match.subtract(const Duration(hours: 6));
    final resolved = known ?? match.add(const Duration(hours: 3));
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixture,
      homeTeam: 'Team A',
      awayTeam: 'Team B',
      league: league,
      country: country,
      matchDate: match,
      market: market,
      probability: probability,
      smartScore: 70,
      confidence: null,
      classification: null,
      qualified: true,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: status,
      actualHomeGoals: 2,
      actualAwayGoals: 1,
      firstSeenAt: created,
      lastSeenAt: resolved,
      resolvedAt: resolved,
      quotedOdd: odd,
    );
  }

  test('P21W.4: uses only settled outcomes known before each prediction', () {
    final samples = [
      for (var i = 0; i < 130; i++)
        record(
          fixture: i + 1,
          status: i % 5 == 0
              ? SmartBetAnalysisStatus.wrong
              : SmartBetAnalysisStatus.correct,
        ),
    ];
    final replay = service.evaluate(records: samples, asOf: cutoff);
    final segment = replay.segments.single;
    expect(segment.eligibleFixtures, 130);
    expect(segment.evaluatedFixtures, 79);
    expect(segment.distinctValidationDays, 79);
    expect(segment.originalBrier, isNotNull);
    expect(segment.shadowBrier, lessThan(segment.originalBrier!));
    expect(segment.brierImprovement, greaterThan(0));
    expect(segment.warrantsFurtherResearch, true);
    expect(samples.first.probability, 0.6); // Forecast remains unchanged.
  });

  test('P21W.4: refuses same-day hindsight even with 120 settled labels', () {
    final kickoff = DateTime.utc(2026, 8, 1, 20);
    final samples = [
      for (var i = 0; i < 120; i++)
        record(fixture: i + 1, kickoff: kickoff,
          firstSeen: kickoff.subtract(const Duration(hours: 5)),
          known: kickoff.add(const Duration(hours: 3))),
    ];
    final segment = service.evaluate(records: samples, asOf: cutoff)
        .segments.single;
    expect(segment.eligibleFixtures, 120);
    expect(segment.evaluatedFixtures, 0);
    expect(segment.shadowBrier, isNull);
    expect(segment.warrantsFurtherResearch, false);
  });

  test('P21W.4: fewer than 50 prior outcomes cannot calibrate', () {
    final segment = service.evaluate(records: [
      for (var i = 0; i < 40; i++) record(fixture: i + 1),
    ], asOf: cutoff).segments.single;
    expect(segment.evaluatedFixtures, 0);
    expect(segment.originalBrier, isNull);
  });

  test('P21W.4: conflicting fixture excluded and exact repeats deduplicated', () {
    final one = record(fixture: 1, odd: 1.20);
    final repeatWithOtherOdd = record(fixture: 1, odd: 3.30);
    final conflict = record(fixture: 1, status: SmartBetAnalysisStatus.wrong);
    final report = service.evaluate(records: [
      one, repeatWithOtherOdd, conflict, record(fixture: 2),
    ], asOf: cutoff);
    expect(report.duplicateRecords, 1);
    expect(report.conflictingFixtureMarkets, 1);
    expect(report.segments.single.eligibleFixtures, 1);
  });

  test('P21W.4: odds never influence forecast, sorting or Brier', () {
    final base = [
      for (var i = 0; i < 100; i++) record(
        fixture: i + 1,
        status: i.isEven
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong,
        odd: 1.20,
      ),
    ];
    final repriced = [
      for (var i = 0; i < 100; i++) record(
        fixture: i + 1,
        status: i.isEven
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong,
        odd: 100.0,
      ),
    ];
    final a = service.evaluate(records: base, asOf: cutoff).segments.single;
    final b = service.evaluate(records: repriced, asOf: cutoff).segments.single;
    expect(a.evaluatedFixtures, b.evaluatedFixtures);
    expect(a.originalBrier, b.originalBrier);
    expect(a.shadowBrier, b.shadowBrier);
    expect(a.meanAdjustmentPoints, b.meanAdjustmentPoints);
  });

  test('P21W.4: partitions by engine, country, league and market', () {
    final report = service.evaluate(records: [
      record(fixture: 1),
      record(fixture: 2, country: 'England'),
      record(fixture: 3, league: 'Serie B'),
      record(fixture: 4, market: 'OVER 2.5'),
      record(fixture: 5, engine: SmartBetAnalysisEngine.diego),
    ], asOf: cutoff);
    expect(report.segments.length, 5);
    expect(report.segments.every((s) => s.evaluatedFixtures == 0), true);
  });

  test('P21W.4: exclude late, non-prospective, invalid or future outcomes', () {
    final kickoff = DateTime.utc(2026, 10, 10, 20);
    final report = service.evaluate(records: [
      record(fixture: 1, kickoff: kickoff, prospective: false),
      record(fixture: 2, kickoff: kickoff, firstSeen: kickoff),
      record(fixture: 3, kickoff: kickoff, known: cutoff.add(const Duration(days: 1))),
      record(fixture: 4, kickoff: kickoff, probability: double.nan),
      record(fixture: 5, kickoff: kickoff, known: kickoff),
      record(fixture: 6, kickoff: cutoff.add(const Duration(days: 2))),
      record(fixture: 7, kickoff: kickoff),
    ], asOf: cutoff);
    expect(report.rejectedRecords, 6);
    expect(report.segments.single.eligibleFixtures, 1);
  });

  test('P21W.4: data ordering does not change replay metrics', () {
    final samples = [
      for (var i = 0; i < 105; i++)
        record(fixture: i + 1,
          status: i % 3 == 0
              ? SmartBetAnalysisStatus.wrong
              : SmartBetAnalysisStatus.correct),
    ];
    final a = service.evaluate(records: samples, asOf: cutoff).segments.single;
    final b = service.evaluate(records: samples.reversed, asOf: cutoff).segments.single;
    expect(a.evaluatedFixtures, b.evaluatedFixtures);
    expect(a.originalBrier, b.originalBrier);
    expect(a.shadowBrier, b.shadowBrier);
  });
}
