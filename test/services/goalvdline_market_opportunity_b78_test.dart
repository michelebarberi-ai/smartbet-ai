import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_market_opportunity_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_league_market_reliability_service.dart';

SmartBetLeagueMarketReliability evidence({
  int n = 120,
  int days = 20,
  double gap = 0,
  String market = 'UNDER 4.5',
}) => SmartBetLeagueMarketReliability(
  engine: SmartBetAnalysisEngine.smartBet,
  country: 'Italia',
  league: 'Serie A',
  market: market,
  sampleSize: n,
  correct: (n * 0.8).round(),
  wrong: n - (n * 0.8).round(),
  distinctMatchDays: days,
  probabilitySampleSize: n,
  observedAccuracyPercent: 80,
  wilsonLower95Percent: 71,
  wilsonUpper95Percent: 87,
  averagePredictedPercent: 80,
  calibrationGapPoints: gap,
  brierScore: 0.17,
  evidenceLevel: SmartBetLeagueMarketEvidenceLevel.signal,
);

SmartBetLeagueMarketReliabilityReport report(
  List<SmartBetLeagueMarketReliability> items,
) => SmartBetLeagueMarketReliabilityReport(
  asOf: DateTime.utc(2026, 11, 22),
  uniqueEligibleRecords: 120,
  skippedUnsafeRecords: 0,
  duplicateRecords: 0,
  conflictingFixtureMarkets: 0,
  segments: items,
);

void main() {
  const service = GoalVdLineMarketOpportunityService();
  const sporting = {
    'UNDER 5.5': 96.0,
    'UNDER 4.5': 87.0,
    'OVER 1.5': 78.0,
  };

  test('B78: bookmaker odds cannot alter sporting order or primary forecast', () {
    final low = service.compare(
      sportingPercent: sporting, country: 'Italia', league: 'Serie A',
      quotedOdds: {'UNDER 4.5': 1.25, 'UNDER 5.5': 1.09},
      selectedMarket: 'UNDER 4.5',
    );
    final high = service.compare(
      sportingPercent: sporting, country: 'Italia', league: 'Serie A',
      quotedOdds: {'UNDER 4.5': 2.30, 'UNDER 5.5': 5.50},
      selectedMarket: 'UNDER 4.5',
    );
    expect(low.rankedSportingMarkets.map((x) => x.market),
      high.rankedSportingMarkets.map((x) => x.market));
    expect(low.rankedSportingMarkets.first.market, 'UNDER 5.5');
    expect(low.selectedMarketIsTopSporting, isFalse);
    expect(high.selectedMarketIsTopSporting, isFalse);
    expect(low.hasVerifiedValueCandidate, isFalse);
    expect(high.hasVerifiedValueCandidate, isFalse);
  });

  test('B78: quota 1.20 is not playable even if probability is high', () {
    final r = service.compare(
      sportingPercent: {'UNDER 4.5': 93.0},
      country: 'Italia', league: 'Serie A',
      quotedOdds: {'UNDER 4.5': 1.20},
      selectedMarket: 'UNDER 4.5',
    );
    expect(r.selected!.assessment, contains('non giocabile'));
    expect(r.selected!.impliedProbabilityPercent, closeTo(83.333, 0.01));
  });

  test('B78: apparently easy price can be worse than the model estimate', () {
    final r = service.compare(
      sportingPercent: {'UNDER 4.5': 72},
      country: 'Italia', league: 'Serie A',
      quotedOdds: {'UNDER 4.5': 1.25},
      selectedMarket: 'UNDER 4.5',
    );
    expect(r.selected!.nominalEdgePoints, closeTo(-8, 0.001));
    expect(r.selected!.assessment, contains('sotto il pareggio'));
  });

  test('B78: short or unqualified history does not approve a pick', () {
    final r = service.compare(
      sportingPercent: {'UNDER 4.5': 91},
      country: 'Italia', league: 'Serie A',
      history: report([evidence(n: 20, days: 3)]),
      quotedOdds: {'UNDER 4.5': 1.30},
    );
    expect(r.rankedSportingMarkets.single.evidenceIsQualified, isFalse);
    expect(r.rankedSportingMarkets.single.assessment,
      contains('Dati storici insufficienti'));
    expect(r.hasVerifiedValueCandidate, isFalse);
  });

  test('B78: overconfident historical model is flagged even with edge', () {
    final r = service.compare(
      sportingPercent: {'UNDER 4.5': 91.0},
      country: 'Italia', league: 'Serie A',
      history: report([evidence(gap: -9)]),
      quotedOdds: {'UNDER 4.5': 1.30},
    );
    expect(r.selected, isNull);
    expect(r.rankedSportingMarkets.single.evidenceIsQualified, isTrue);
    expect(r.rankedSportingMarkets.single.assessment, contains('sovrastimare'));
  });

  test('B78: valid sample is still an indicator, not guaranteed profit', () {
    final r = service.compare(
      sportingPercent: {'UNDER 4.5': 91.0},
      country: 'Italia', league: 'Serie A',
      history: report([evidence()]),
      quotedOdds: {'UNDER 4.5': 1.30},
    );
    expect(r.rankedSportingMarkets.single.assessment,
      contains('indicativo'));
    expect(r.hasVerifiedValueCandidate, isFalse);
  });

  test('B78: missing odds and invalid probabilities are never fabricated', () {
    final r = service.compare(
      sportingPercent: {
        'UNDER 4.5': 88,
        'OVER 1.5': double.nan,
        'GOAL': -2,
      },
      country: 'Italia', league: 'Serie A',
      quotedOdds: {'UNDER 4.5': double.infinity},
    );
    expect(r.rankedSportingMarkets.length, 1);
    expect(r.rankedSportingMarkets.single.actualOdd, isNull);
    expect(r.rankedSportingMarkets.single.assessment,
      contains('non verificabile'));
  });
}
