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
}
