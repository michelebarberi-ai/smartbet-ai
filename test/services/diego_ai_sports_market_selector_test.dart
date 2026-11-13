import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/diego_ai_market_probability_service.dart';
import 'package:smartbet_ai_new/services/diego_ai_sports_market_selector.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';

DiegoAiMarketProbability market(String name, double probability) =>
    DiegoAiMarketProbability(market: name, probability: probability);

FixtureMarketOdds quotes(Map<String, double> values) {
  return FixtureMarketOdds(
    fixtureId: 1001,
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
}

void main() {
  final probabilities = [
    market('GOAL', 0.80),
    market('OVER 2.5', 0.72),
    market('1', 0.65),
  ];

  test('Sceglie il mercato sportivamente piu probabile', () {
    final pick = DiegoAiSportsMarketSelector.bestPlayable(
      markets: probabilities,
      odds: quotes({'GOAL': 1.40, 'OVER 2.5': 3.20, '1': 5.50}),
    );

    expect(pick?.market, 'GOAL');
    expect(pick?.probability, 0.80);
  });

  test('Aumentare la quota non modifica il pronostico', () {
    final first = DiegoAiSportsMarketSelector.bestPlayable(
      markets: probabilities,
      odds: quotes({'GOAL': 1.40, 'OVER 2.5': 1.80}),
    );

    final second = DiegoAiSportsMarketSelector.bestPlayable(
      markets: probabilities,
      odds: quotes({'GOAL': 1.40, 'OVER 2.5': 9.50}),
    );

    expect(first?.market, 'GOAL');
    expect(second?.market, first?.market);
    expect(second?.probability, first?.probability);
  });

  test('Sotto quota 1.20: solo alternativa quotata, non nuovo forecast', () {
    final pick = DiegoAiSportsMarketSelector.bestPlayable(
      markets: probabilities,
      odds: quotes({'GOAL': 1.19, 'OVER 2.5': 1.60, '1': 2.50}),
    );

    expect(pick?.market, 'OVER 2.5');
    expect(pick?.probability, 0.72);
  });

  test('Quote assenti: nessuna selezione giocabile', () {
    final pick = DiegoAiSportsMarketSelector.bestPlayable(
      markets: probabilities,
      odds: null,
    );

    expect(pick, isNull);
  });

  test('Probabilita non valide vengono scartate', () {
    final pick = DiegoAiSportsMarketSelector.bestPlayable(
      markets: [
        market('GOAL', double.nan),
        market('OVER 2.5', 1.20),
        market('1', 0.65),
      ],
      odds: quotes({'GOAL': 1.40, 'OVER 2.5': 1.50, '1': 1.80}),
    );

    expect(pick?.market, '1');
  });

  test('Parita di probabilita: scelta deterministica', () {
    final pick = DiegoAiSportsMarketSelector.bestPlayable(
      markets: [market('OVER 2.5', 0.70), market('GOAL', 0.70)],
      odds: quotes({'GOAL': 1.50, 'OVER 2.5': 1.80}),
    );

    expect(pick?.market, 'GOAL');
  });
}
