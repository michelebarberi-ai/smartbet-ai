import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_three_engine_comparison_service.dart';

void main() {
  const service = SmartBetThreeEngineComparisonService();
  final cutoff = DateTime.utc(2026, 11, 18);

  SmartBetAnalysisRecord prediction({
    required int fixture,
    required SmartBetAnalysisEngine engine,
    String market = 'GOAL',
    double probability = 0.7,
    bool hit = true,
    bool qualified = true,
    bool prospective = true,
    String? classification,
    int? resultHome,
    DateTime? resolvedAt,
  }) {
    final kickoff = DateTime.utc(2026, 8, 1).add(Duration(days: fixture));
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixture,
      homeTeam: 'A',
      awayTeam: 'B',
      country: 'Italia',
      league: 'Serie A',
      matchDate: kickoff,
      market: market,
      probability: probability,
      smartScore: null,
      confidence: null,
      classification: engine == SmartBetAnalysisEngine.simulator
          ? (classification ?? 'SIMULATOR_XG_FROM_SMARTBET') : null,
      qualified: engine == SmartBetAnalysisEngine.diego ? qualified : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: hit
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: resultHome ?? 2,
      actualAwayGoals: 1,
      firstSeenAt: kickoff.subtract(const Duration(hours: 8)),
      lastSeenAt: kickoff.add(const Duration(hours: 3)),
      resolvedAt: resolvedAt ?? kickoff.add(const Duration(hours: 3)),
    );
  }

  test('B66: matched fixture+market gets fair paired Brier scores', () {
    final report = service.evaluate(records: [
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.smartBet,
          probability: 0.8),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.diego,
          probability: 0.6),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.simulator,
          probability: 0.7),
      // Same fixture but unrelated market cannot be a comparison pair.
      prediction(fixture: 2, engine: SmartBetAnalysisEngine.smartBet,
          market: 'OVER 2.5'),
      prediction(fixture: 2, engine: SmartBetAnalysisEngine.simulator,
          market: 'GOAL'),
    ], asOf: cutoff);

    expect(report.markets, hasLength(1));
    final metric = report.markets.single;
    expect(metric.market, 'GOAL');
    expect(metric.pairedWithSmartBet, 1);
    expect(metric.pairedWithDiego, 1);
    expect(metric.completeTriplets, 1);
    expect(metric.smartBetBrier, closeTo(0.04, 1e-9));
    expect(metric.simulatorOnSmartBetFixturesBrier, closeTo(0.09, 1e-9));
    expect(metric.diegoBrier, closeTo(0.16, 1e-9));
    expect(metric.simulatorOnDiegoFixturesBrier, closeTo(0.09, 1e-9));
    expect(metric.advantageVsSmartBet, lessThan(0));
    expect(metric.advantageVsDiego, greaterThan(0));
    expect(metric.smartBetResearchSample, isFalse);
  });

  test('B66: unqualified Diego cannot enter simulator comparison', () {
    final report = service.evaluate(records: [
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.diego,
          qualified: false),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.simulator),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.smartBet),
    ], asOf: cutoff);
    expect(report.markets.single.pairedWithDiego, 0);
    expect(report.markets.single.completeTriplets, 0);
    expect(report.markets.single.pairedWithSmartBet, 1);
  });

  test('B66: conflicting outcomes exclude a pair, not crown a winner', () {
    final report = service.evaluate(records: [
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.smartBet,
          hit: true),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.simulator,
          hit: false),
    ], asOf: cutoff);
    expect(report.markets, isEmpty);
  });

  test('B66: contradictory duplicate forecasts are rejected', () {
    final report = service.evaluate(records: [
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.simulator,
          probability: 0.50),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.simulator,
          probability: 0.90),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.smartBet),
    ], asOf: cutoff);
    expect(report.conflictingFixtureMarkets, 1);
    expect(report.markets, isEmpty);
  });

  test('B66: future outcomes and non-prospective forecasts are excluded', () {
    final report = service.evaluate(records: [
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.smartBet,
          prospective: false),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.simulator,
          resolvedAt: cutoff.add(const Duration(days: 1))),
    ], asOf: cutoff);
    expect(report.markets, isEmpty);
    expect(report.rejectedForecastRecords, 2);
  });

  test('B66: duplicate entries do not invent extra matched fixtures', () {
    final smart = prediction(fixture: 1,
        engine: SmartBetAnalysisEngine.smartBet);
    final sim = prediction(fixture: 1,
        engine: SmartBetAnalysisEngine.simulator);
    final report = service.evaluate(
        records: [smart, sim, smart, sim], asOf: cutoff);
    expect(report.markets.single.pairedWithSmartBet, 1);
  });

  test('B66: shared input source is disclosed without independence claim', () {
    final report = service.evaluate(records: [
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.smartBet),
      prediction(fixture: 1, engine: SmartBetAnalysisEngine.simulator,
          classification: 'SIMULATOR_XG_FROM_SMARTBET'),
      prediction(fixture: 2, engine: SmartBetAnalysisEngine.diego),
      prediction(fixture: 2, engine: SmartBetAnalysisEngine.simulator,
          classification: 'SIMULATOR_XG_FROM_DIEGO'),
    ], asOf: cutoff);
    final metric = report.markets.single;
    expect(metric.simulatorSharedSmartBetInputs, 1);
    expect(metric.simulatorSharedDiegoInputs, 1);
    expect(metric.completeTriplets, 0);
  });
}
