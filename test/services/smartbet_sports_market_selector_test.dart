import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_sports_market_selector.dart';

void main() {
  const probabilities = <String, int>{'GOAL': 82, 'OVER 2.5': 75, '1': 70};

  test('Il mercato migliore dipende dalla probabilita', () {
    final pick = SmartBetSportsMarketSelector.bestPlayable(
      sportsProbabilities: probabilities,
      quotedOdds: const {'GOAL': 1.30, 'OVER 2.5': 2.40, '1': 3.50},
    );

    expect(pick?.market, 'GOAL');
    expect(pick?.probability, 82);
  });

  test('Aumentare una quota non cambia il pronostico', () {
    final pick = SmartBetSportsMarketSelector.bestPlayable(
      sportsProbabilities: probabilities,
      quotedOdds: const {'GOAL': 1.30, 'OVER 2.5': 2.40, '1': 20.00},
    );

    expect(pick?.market, 'GOAL');
  });

  test('Il limite di 1.20 e incluso', () {
    final pick = SmartBetSportsMarketSelector.bestPlayable(
      sportsProbabilities: probabilities,
      quotedOdds: const {'GOAL': 1.20, 'OVER 2.5': 2.40},
    );

    expect(pick?.market, 'GOAL');
  });

  test('Quota sotto 1.20 passa al secondo mercato sportivo', () {
    final pick = SmartBetSportsMarketSelector.bestPlayable(
      sportsProbabilities: probabilities,
      quotedOdds: const {'GOAL': 1.19, 'OVER 2.5': 1.50, '1': 5.00},
    );

    expect(pick?.market, 'OVER 2.5');
    expect(pick?.probability, 75);
  });

  test('Mercati senza quote ammissibili vengono esclusi', () {
    final pick = SmartBetSportsMarketSelector.bestPlayable(
      sportsProbabilities: probabilities,
      quotedOdds: const {'GOAL': 1.10, 'OVER 2.5': 1.19},
    );

    expect(pick, isNull);
  });

  test('Il ranking puro non dipende da quote', () {
    final ranked = SmartBetSportsMarketSelector.rankedMarkets(probabilities);

    expect(ranked.map((entry) => entry.key).toList(), [
      'GOAL',
      'OVER 2.5',
      '1',
    ]);
  });

  test('P20.6: forecast survives missing Sisal prices without invented coupon', () {
    final recommendation = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: const {'GOAL': 82, 'OVER 2.5': 75, '2': 11},
      quotedOdds: const {},
      minimumProbability: 65,
    )!;
    expect(recommendation.primary.market, 'GOAL');
    expect(recommendation.primary.probability, 82);
    expect(recommendation.primaryOdd, isNull);
    expect(recommendation.couponPick, isNull);
    expect(recommendation.usesAlternative, false);
  });

  test('P20.6: an unplayable top odd never changes primary forecast', () {
    final recommendation = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: const {'GOAL': 82, 'OVER 2.5': 75, '2': 11},
      quotedOdds: const {'GOAL': 1.19, 'OVER 2.5': 1.20, '2': 20},
      minimumProbability: 65,
    )!;
    expect(recommendation.primary.market, 'GOAL');
    expect(recommendation.primary.probability, 82);
    expect(recommendation.couponPick?.market, 'OVER 2.5');
    expect(recommendation.couponPick?.probability, 75);
    expect(recommendation.couponPick?.odd, 1.20);
    expect(recommendation.usesAlternative, true);
  });

  test('P20.6: weak 7-13% outcomes cannot rescue an absent high-confidence odd', () {
    final recommendation = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: const {'GOAL': 82, '2': 13, 'X': 7},
      quotedOdds: const {'GOAL': 1.10, '2': 5, 'X': 12},
      minimumProbability: 65,
    )!;
    expect(recommendation.primary.market, 'GOAL');
    expect(recommendation.couponPick, isNull);
  });

  test('P20.6: changing only quoted odds does not reorder sporting forecasts', () {
    const probabilities = <String, int>{'GOAL': 82, 'OVER 2.5': 75, '1': 70};
    const quotes = <Map<String, double>>[
      {},
      {'GOAL': 1.19, 'OVER 2.5': 1.20, '1': 7.50},
      {'GOAL': 2.40, 'OVER 2.5': 9.99, '1': 1.20},
    ];
    final originalRank = SmartBetSportsMarketSelector.rankedMarkets(probabilities);
    for (final odds in quotes) {
      final recommendation = SmartBetSportsMarketSelector.recommend(
        sportsProbabilities: probabilities,
        quotedOdds: odds,
      )!;
      expect(recommendation.primary.market, 'GOAL');
      expect(recommendation.primary.probability, 82);
      expect(SmartBetSportsMarketSelector.rankedMarkets(probabilities),
        orderedEquals(originalRank));
    }
  });

}
