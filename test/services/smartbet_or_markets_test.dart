import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_market_probability_service.dart';
import 'package:smartbet_ai_new/services/smartbet_multi_market_selection_service.dart';

const a = AnalysisResult(
  smartScore: 78,
  homeProbability: 60,
  drawProbability: 25,
  awayProbability: 15,
  over15Probability: 85,
  under15Probability: 15,
  over25Probability: 59,
  under25Probability: 41,
  goalProbability: 72,
  noGoalProbability: 28,
  expectedHomeGoals: 1.8,
  expectedAwayGoals: 1.2,
  prediction: '1',
  valueBet: '',
  risk: 'MEDIO',
  explanation: 'Test OR',
);

FixtureMarketOdds quotes(Map<String, double> values) => FixtureMarketOdds(
  fixtureId: 711,
  matchWinner: null,
  bookmakerCount: 1,
  bestByOutcome: {
    for (final entry in values.entries)
      entry.key: BestOdd(
        outcome: entry.key,
        odd: entry.value,
        bookmakerId: 5,
        bookmakerName: 'Bookmaker Test',
      ),
  },
);

void main() {
  test('B47: 14 OR markets have explicit lines and positive probability', () {
    expect(SmartBetMarketProbabilityService.orMarkets.length, 14);
    for (final market in SmartBetMarketProbabilityService.orMarkets) {
      expect(market, contains(' O '));
      final probability =
          SmartBetMarketProbabilityService.probabilityFor(a, market);
      expect(probability, inInclusiveRange(1, 100), reason: market);
    }
  });

  test('B47: OR union contains either constituent event, not AND', () {
    final or = SmartBetMarketProbabilityService.probabilityFor(
      a, 'GOAL O OVER 2.5',
    );
    final and = SmartBetMarketProbabilityService.probabilityFor(
      a, 'GOAL + O2.5',
    );
    // The GOAL marginal in AnalysisResult can use a separate model;
    // this OR is evaluated from the common joint score distribution.
    expect(or, greaterThanOrEqualTo(and));
    expect(or, greaterThanOrEqualTo(a.over25Probability));
    expect(or, greaterThan(and));

    final xOrUnder = SmartBetMarketProbabilityService.probabilityFor(
      a, 'X O UNDER 3.5',
    );
    final under = SmartBetMarketProbabilityService.probabilityFor(
      a, 'UNDER 3.5',
    );
    expect(xOrUnder, greaterThanOrEqualTo(under));
  });

  test('B47: OR markets are offered to combinations but never get fake odds', () {
    final noQuote = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({}),
      families: ['MERCATI OPPURE'],
    );
    expect(noQuote, isNull);

    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'GOAL O OVER 2.5': 1.27}),
      families: ['MERCATI OPPURE'],
    );
    expect(result?.market, 'GOAL O OVER 2.5');
    expect(result?.odd, 1.27);
    expect(result?.bookmaker, 'Bookmaker Test');
  });

  test('B47: exact 1.20 is not a playable OR market', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'GOAL O OVER 2.5': 1.20}),
      families: ['MERCATI OPPURE'],
    );
    expect(result, isNull);
  });
}
