import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/goalvdline_coupon_market_policy.dart';
import 'package:smartbet_ai_new/services/smartbet_market_probability_service.dart';

AnalysisResult basicAnalysis() => const AnalysisResult(
  smartScore: 72,
  homeProbability: 53, drawProbability: 25, awayProbability: 22,
  over15Probability: 75, under15Probability: 25,
  over25Probability: 56, under25Probability: 44,
  goalProbability: 62, noGoalProbability: 38,
  expectedHomeGoals: 1.75, expectedAwayGoals: 0.9,
  prediction: '1', valueBet: '1',
  risk: 'moderato', explanation: 'analisi',
);

void main() {
  test('B78: Crea Schedina has ONLY requested simple sporting families', () {
    const core = GoalVdLineCouponMarketPolicy.coreMarketOrder;
    expect(core.toSet().length, core.length);
    for (final market in [
      '1','X','2','1X','X2','12',
      'OVER 1.5','UNDER 1.5','OVER 2.5','UNDER 2.5',
      'OVER 3.5','UNDER 3.5','OVER 4.5','UNDER 4.5',
      'MULTIGOL 1-4','MULTIGOL 2-4','MULTIGOL 2-5',
      'MULTIGOL 3-5','GOAL','NO GOAL',
      'HCP EURO CASA -1 1','HCP EURO CASA 1 2',
      'HCP ASIA CASA -0.5','HCP ASIA OSPITE 0.5',
    ]) {
      expect(GoalVdLineCouponMarketPolicy.isAllowedCouponMarket(market),
          isTrue, reason: market);
    }

    for (final excluded in [
      'DNB CASA','DNB OSPITE','CASA SEGNA','OSPITE SEGNA',
      'CASA 2+ GOL','OSPITE 3+ GOL','CASA SEGNA PRIMA',
      'GOAL + O2.5','NO GOAL + U2.5',
      '1X + O1.5','X2 + U3.5','GOAL O OVER 2.5',
      '1X O UNDER 3.5','HCP EURO CASA 3 1','HCP EURO CASA -3 2',
      'HCP ASIA CASA -2.5',
      '1T 1','2T X','CORNER OVER 8.5','TIRI PORTA OVER 6.5',
    ]) {
      expect(GoalVdLineCouponMarketPolicy.isAllowedCouponMarket(excluded),
          isFalse, reason: excluded);
    }
  });

  test('B78: specialty models remain available for full analysis elsewhere',
      () {
    expect(SmartBetMarketProbabilityService.extendedMarkets,
        contains('GOAL O OVER 2.5'));
    expect(SmartBetMarketProbabilityService.extendedMarkets,
        contains('CASA SEGNA'));
    expect(SmartBetMarketProbabilityService.extendedMarkets,
        contains('1X + O1.5'));
    expect(SmartBetMarketProbabilityService.extendedMarkets,
        contains('MULTIGOL 1-4'));
  });

  test('B78: handicap ranking uses sport-only fixture-independent catalogue',
      () {
    final candidates = GoalVdLineCouponMarketPolicy.sportingHandicaps(
      basicAnalysis(),
    );
    expect(candidates, isNotEmpty);
    expect(candidates.every((c) =>
      GoalVdLineCouponMarketPolicy.isAllowedCouponMarket(c.market)), isTrue);
    expect(candidates.every((c) => c.probability > 0 &&
        c.probability <= 100), isTrue);
    expect(candidates.any((c) => c.market.startsWith('HCP EURO CASA')), isTrue);
    expect(candidates.any((c) => c.market.startsWith('HCP ASIA')), isTrue);
    expect(candidates.any((c) => c.market.contains(' -3 ')), isFalse);
  });

  test('B78: no xG means no invented handicap probabilities', () {
    const analysis = AnalysisResult(
      smartScore: 70, homeProbability: 60,
      drawProbability: 20, awayProbability: 20,
      expectedHomeGoals: 0, expectedAwayGoals: 0,
      prediction: '1', valueBet: '1',
      risk: 'moderato', explanation: '',
    );
    expect(GoalVdLineCouponMarketPolicy.sportingHandicaps(analysis), isEmpty);
  });
}
