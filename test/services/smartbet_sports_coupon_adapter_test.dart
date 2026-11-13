import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_sports_coupon_adapter.dart';
import 'package:smartbet_ai_new/services/smartbet_market_probability_service.dart';

void main() {
  AnalysisResult analysis() => const AnalysisResult(
    smartScore: 83,
    homeProbability: 70,
    drawProbability: 20,
    awayProbability: 10,
    goalProbability: 82,
    over25Probability: 75,
    prediction: 'GOAL',
    valueBet: '',
    risk: 'Basso',
    explanation: '',
    shouldBet: false,
    stakeOutcome: '2',
    stakeOdd: 20.0,
  );

  FixtureMarketOdds odds(Map<String, double> values) => FixtureMarketOdds(
    fixtureId: 123,
    matchWinner: null,
    bookmakerCount: 1,
    bestByOutcome: {
      for (final entry in values.entries)
        entry.key: BestOdd(
          outcome: entry.key,
          odd: entry.value,
          bookmakerId: 1,
          bookmakerName: 'Test',
        ),
    },
  );

  test('Selezione indipendente dallo Stake Engine', () {
    final pick = SmartBetSportsCouponAdapter.bestPlayable(
      analysis: analysis(),
      odds: odds({'GOAL': 1.30, '1': 3.50, '2': 20.0}),
    );

    expect(pick?.market, 'GOAL');
    expect(pick?.probability, 82);
  });

  test('Una quota maggiore non cambia la preferenza', () {
    final pick = SmartBetSportsCouponAdapter.bestPlayable(
      analysis: analysis(),
      odds: odds({'GOAL': 1.30, '1': 50.0}),
    );

    expect(pick?.market, 'GOAL');
  });

  test('Sotto 1.20 passa al mercato successivo', () {
    final pick = SmartBetSportsCouponAdapter.bestPlayable(
      analysis: analysis(),
      odds: odds({'GOAL': 1.19, 'OVER 2.5': 1.50, '1': 3.50}),
    );

    expect(pick?.market, 'OVER 2.5');
  });

  test('B47: OR quota reale o nessun mercato OPPURE giocabile', () {
    final market = SmartBetMarketProbabilityService.orMarkets.first;
    final unquoted = SmartBetSportsCouponAdapter.allPlayable(
      analysis: analysis(), odds: odds({'GOAL': 1.19}),
    );
    expect(unquoted.any((e) => e.market == market), false);
    final withQuote = SmartBetSportsCouponAdapter.allPlayable(
      analysis: analysis(), odds: odds({market: 1.28}),
    );
    expect(withQuote.any((e) => e.market == market), true);
  });

  test('Senza una quota ammissibile non sceglie', () {
    final pick = SmartBetSportsCouponAdapter.bestPlayable(
      analysis: analysis(),
      odds: odds({'GOAL': 1.19, 'OVER 2.5': 1.12}),
    );

    expect(pick, isNull);
  });
}
