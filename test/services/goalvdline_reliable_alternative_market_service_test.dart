import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_reliable_alternative_market_service.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_match_simulation_service.dart';

void main() {
  const planner = GoalVdLineReliableAlternativeMarketService();
  const simulator = SmartBetMatchSimulationService();

  SmartBetSimulationResult match({
    double home = 3.2,
    double away = 0.8,
    double quality = 0.85,
  }) => simulator.simulate(SmartBetMatchSimulationInput(
        expectedHomeGoals: home,
        expectedAwayGoals: away,
        dataQuality: quality,
      ));

  FixtureMarketOdds feed(Map<String, double> marketOdds) =>
      FixtureMarketOdds(
        fixtureId: 7701,
        matchWinner: null,
        bookmakerCount: 1,
        bestByOutcome: {
          for (final entry in marketOdds.entries)
            entry.key: BestOdd(
              outcome: entry.key,
              odd: entry.value,
              bookmakerId: 17,
              bookmakerName: 'Bookmaker di test',
            ),
        },
      );

  test('B65: prima il pronostico 1, poi l alternativa piu probabile quotata', () {
    final result = planner.evaluate(
      engineId: 'SmartCore',
      primaryMarket: '1',
      simulation: match(),
      odds: feed({
        '1': 1.15,
        '1X': 1.12,
        'CASA SEGNA': 1.10,
        'OVER 1.5': 1.27,
        'CASA 2+ GOL': 1.49,
        'HCP EURO CASA -1 1': 1.75,
      }),
    );

    expect(result.primaryMarket, '1');
    expect(result.primaryFeedOdd, 1.15);
    expect(result.suggestedFallback, isNotNull);
    expect(result.suggestedFallback!.market, 'OVER 1.5');
    expect(result.quotedAlternatives.map((item) => item.market),
        contains('HCP EURO CASA -1 1'));
    expect(result.suggestedFallback!.probability,
        greaterThan(result.quotedAlternatives.last.probability));
    expect(result.explanation, contains('non e certificata'));
  });

  test('B65: 3-1 copre handicap -1 ma non attribuisce certezza al mercato', () {
    final result = planner.evaluate(
      engineId: 'Diego',
      primaryMarket: '1',
      simulation: match(),
    );
    final handicap = result.sportsAlternatives.singleWhere(
      (item) => item.market == 'HCP EURO CASA -1 1',
    );
    expect(handicap.probability, greaterThan(0));
    expect(handicap.probability, lessThan(result.primaryProbability));
    expect(result.suggestedFallback, isNull);
  });

  test('B65: quota piu alta non sostituisce il ranking sportivo', () {
    final input = match();
    final one = planner.evaluate(
      engineId: 'SmartCore', primaryMarket: '1', simulation: input,
      odds: feed({'1': 1.10, 'OVER 1.5': 1.25, 'CASA 2+ GOL': 2.30}),
    );
    final two = planner.evaluate(
      engineId: 'SmartCore', primaryMarket: '1', simulation: input,
      odds: feed({'1': 1.10, 'OVER 1.5': 1.65, 'CASA 2+ GOL': 1.30}),
    );
    expect(one.suggestedFallback?.market, 'OVER 1.5');
    expect(two.suggestedFallback?.market, 'OVER 1.5');
    expect(
      one.sportsAlternatives.map((item) => item.market).toList(),
      two.sportsAlternatives.map((item) => item.market).toList(),
    );
  });

  test('B65: quota primaria adeguata mantiene il mercato 1', () {
    final result = planner.evaluate(
      engineId: 'SmartCore', primaryMarket: '1',
      simulation: match(),
      odds: feed({'1': 1.32, 'OVER 1.5': 1.27}),
    );
    expect(result.primaryFeedOdd, 1.32);
    expect(result.suggestedFallback, isNull);
    expect(result.quotedAlternatives, isNotEmpty);
  });

  test('B65: assenza quote non produce mercati fittizi giocabili', () {
    final result = planner.evaluate(
      engineId: 'Terzo motore',
      primaryMarket: '1',
      simulation: match(),
    );
    expect(result.sportsAlternatives, isNotEmpty);
    expect(result.quotedAlternatives, isEmpty);
    expect(result.suggestedFallback, isNull);
  });

  test('B65: rispetta la soglia >1.20 e quella sportiva', () {
    final result = planner.evaluate(
      engineId: 'SmartCore', primaryMarket: '1',
      simulation: match(), minimumProbability: 0.80,
      odds: feed({
        '1': 1.15,
        'OVER 1.5': 1.20,
        'CASA 2+ GOL': 1.23,
        'HCP EURO CASA -1 1': 1.90,
      }),
    );
    expect(result.quotedAlternatives.every(
      (alt) => alt.odd > 1.20 && alt.probability >= 0.80,
    ), isTrue);
    expect(result.quotedAlternatives.map((alt) => alt.market),
      isNot(contains('OVER 1.5')));
  });

  test('B65: dati insufficienti non consentono un fallback', () {
    final result = planner.evaluate(
      engineId: 'SmartCore',
      primaryMarket: '1',
      simulation: match(quality: 0.4),
      odds: feed({'1': 1.15, 'OVER 1.5': 1.44}),
    );
    expect(result.suggestedFallback, isNull);
    expect(result.quotedAlternatives, isEmpty);
    expect(result.explanation, contains('Qualita dati insufficiente'));
  });

  test('B65: i tre motori mantengono previsioni indipendenti', () {
    final odds = feed({'1': 1.15, 'OVER 1.5': 1.42});
    final smart = planner.evaluate(
      engineId: 'SmartCore', primaryMarket: '1',
      simulation: match(home: 3.2, away: 0.8), odds: odds,
    );
    final diego = planner.evaluate(
      engineId: 'Diego AI', primaryMarket: '1',
      simulation: match(home: 1.3, away: 1.1), odds: odds,
    );
    expect(smart.engineId, 'SmartCore');
    expect(diego.engineId, 'Diego AI');
    expect(smart.primaryProbability, isNot(diego.primaryProbability));
    expect(smart.sportsAlternatives, isNot(same(diego.sportsAlternatives)));
  });

  test('B65: non spaccia X2 o vittoria ospite come coerenti con 1', () {
    final result = planner.evaluate(
      engineId: 'SmartCore',
      primaryMarket: '1', simulation: match(),
    );
    expect(result.sportsAlternatives.map((alt) => alt.market),
      isNot(contains('X2')));
    expect(result.sportsAlternatives.map((alt) => alt.market),
      isNot(contains('2')));
  });

  test('B65: non inventa una selezione quando il mercato non e calcolato', () {
    expect(() => planner.evaluate(
      engineId: 'SmartCore', primaryMarket: 'HANDICAP ASIATICO',
      simulation: match(),
    ), throwsArgumentError);
  });
}
