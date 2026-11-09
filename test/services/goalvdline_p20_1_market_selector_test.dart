import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_sports_market_selector.dart';

void main() {
  test('P20.1: tutti i mercati mantengono ranking sportivo, quote e audit', () {
    const probabilities = <String, int>{
      'OVER 1.5': 88,
      'GOAL': 76,
      'UNDER 2.5': 73,
      'NO GOAL': 66,
      'X': 61,
    };
    const odds = <String, double>{
      'OVER 1.5': 1.10, // sotto quota minima
      'GOAL': 1.70,
      'UNDER 2.5': 1.60,
      'NO GOAL': 1.80,
      'X': 3.10,
    };
    final picks = SmartBetSportsMarketSelector.allPlayable(
      sportsProbabilities: probabilities,
      quotedOdds: odds,
      blockedMarkets: ['BTTS NO'], // alias del mercato NO GOAL
    );
    expect(picks.map((item) => item.market).toList(), [
      'GOAL',
      'UNDER 2.5',
      'X',
    ]);
    expect(picks.map((item) => item.probability).toList(), [76, 73, 61]);
    final best = SmartBetSportsMarketSelector.bestPlayable(
      sportsProbabilities: probabilities,
      quotedOdds: odds,
      blockedMarkets: ['BTTS NO'],
    );
    expect(best?.market, picks.first.market);
    expect(best?.odd, picks.first.odd);
  });

  test('P20.1: non inventa quote e non accetta NaN o Infiniti', () {
    final picks = SmartBetSportsMarketSelector.allPlayable(
      sportsProbabilities: {'GOAL': 78, 'X': 70, '1': 69},
      quotedOdds: {'GOAL': double.nan, 'X': double.infinity},
    );
    expect(picks, isEmpty);
  });
}
