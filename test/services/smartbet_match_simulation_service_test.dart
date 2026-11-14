import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_match_simulation_service.dart';

void main() {
  const simulator = SmartBetMatchSimulationService();
  SmartBetSimulationResult run(
    double h,
    double a, {
    double shared = 0,
    double dataQuality = 1,
  }) => simulator.simulate(
    SmartBetMatchSimulationInput(
      expectedHomeGoals: h,
      expectedAwayGoals: a,
      sharedGoalIntensity: shared,
      dataQuality: dataQuality,
    ),
  );

  test('1X2 sempre normalizzato', () {
    final r = run(1.8, 1.2);
    expect(r.homeWin + r.draw + r.awayWin, closeTo(1, 1e-10));
    expect(r.truncatedTailProbability, lessThan(1e-6));
  });

  test('OVER e UNDER sono complementari per tutti i limiti', () {
    final r = run(1.4, 1.5);
    for (final t in [0, 1, 2, 3, 4]) {
      expect(
        r.probabilityFor('OVER $t.5') + r.probabilityFor('UNDER $t.5'),
        closeTo(1, 1e-10),
      );
    }
  });

  test('B47: mercati OPPURE sono unioni sulla stessa distribuzione', () {
    final r = run(1.8, 1.2);
    final goalOrOver = r.probabilityFor('GOAL O OVER 1.5');

    // GOAL implica sempre due reti: unione identica a OVER 1.5.
    expect(goalOrOver, closeTo(r.probabilityFor('OVER 1.5'), 1e-10));
    expect(
      r.probabilityFor('X O UNDER 3.5'),
      greaterThanOrEqualTo(r.probabilityFor('UNDER 3.5')),
    );
    expect(
      r.probabilityFor('X O UNDER 3.5'),
      greaterThanOrEqualTo(r.draw),
    );
    expect(
      r.probabilityFor('1X O OVER 2.5'),
      greaterThanOrEqualTo(r.probabilityFor('1X')),
    );
    expect(
      r.probabilityFor('GOAL O OVER 2.5'),
      greaterThanOrEqualTo(r.probabilityFor('OVER 2.5')),
    );
  });

  test('B47: tutti i 14 OR sono valori finiti e non una quota', () {
    final r = run(1.2, 1.1);
    final markets = r.marketProbabilities.keys
        .where((market) => market.contains(' O ')).toList();
    expect(markets.length, 14);
    for (final market in markets) {
      final p = r.probabilityFor(market);
      expect(p.isFinite, isTrue, reason: market);
      expect(p, inInclusiveRange(0, 1), reason: market);
    }
  });

  test('Goal e No Goal sono complementari', () {
    final r = run(1.2, 0.9);
    expect(
      r.probabilityFor('GOAL') + r.probabilityFor('NO GOAL'),
      closeTo(1, 1e-10),
    );
  });

  test('doppia chance coerente con i singoli esiti', () {
    final r = run(1.8, 0.6);
    expect(r.probabilityFor('1X'), closeTo(r.homeWin + r.draw, 1e-10));
    expect(r.probabilityFor('X2'), closeTo(r.draw + r.awayWin, 1e-10));
    expect(r.probabilityFor('12'), closeTo(r.homeWin + r.awayWin, 1e-10));
  });

  test('zero gol attesi => 0-0 certo', () {
    final r = run(0, 0);
    expect(r.draw, closeTo(1, 1e-12));
    expect(r.exactScoreProbability(0, 0), closeTo(1, 1e-12));
    expect(r.probabilityFor('NO GOAL'), closeTo(1, 1e-12));
    expect(r.probabilityFor('UNDER 2.5'), closeTo(1, 1e-12));
  });

  test('squadre simmetriche => uguale probabilita 1 e 2', () {
    final r = run(1.3, 1.3);
    expect(r.homeWin, closeTo(r.awayWin, 1e-10));
  });

  test('piu gol attesi casa aumenta la probabilita di vittoria', () {
    expect(run(2.3, 0.9).homeWin, greaterThan(run(1.1, 0.9).homeWin));
  });

  test('componente comune cambia la probabilita del pareggio', () {
    expect(run(1.5, 1.5, shared: 0.4).draw, greaterThan(run(1.5, 1.5).draw));
  });

  test('massima media gestita e coda sotto controllo', () {
    final r = run(6, 6, shared: 1.0);
    expect(r.truncatedTailProbability, lessThan(1e-6));
  });

  test('punteggi ordinati e somma della distribuzione 1', () {
    final r = run(1.3, 0.8);
    final top = r.topExactScores(count: 4);
    expect(top.length, 4);
    expect(top.first.probability, greaterThanOrEqualTo(top.last.probability));
    expect(
      r.exactScores.fold<double>(0, (sum, x) => sum + x.probability),
      closeTo(1, 1e-9),
    );
  });

  test('multigol deriva dalla stessa distribuzione', () {
    final r = run(1.1, 1.2);
    expect(r.probabilityFor('MULTIGOL 1-3'), inInclusiveRange(0, 1));
    expect(r.probabilityFor('MULTIGOL 2-5'), inInclusiveRange(0, 1));
    expect(
      r.probabilityFor('MULTIGOL 1-4'),
      greaterThanOrEqualTo(r.probabilityFor('MULTIGOL 1-3')),
    );
  });

  test('rifiuta dati non validi e soglie impossibili', () {
    expect(() => run(-1, 1), throwsArgumentError);
    expect(() => run(8, 1), throwsArgumentError);
    expect(() => run(1, 1, shared: 1.2), throwsArgumentError);
    expect(() => run(1, 1, dataQuality: 1.2), throwsArgumentError);
    expect(() => run(double.nan, 1), throwsArgumentError);
    expect(
      () => run(1, 1).probabilityFor('QUOTA BOOKMAKER'),
      throwsArgumentError,
    );
  });

  test('X Premium mostra tutte le partite ordinate in due gruppi', () {
    final matches = [
      SmartBetXPremiumCandidate(fixtureId: 'c', simulation: run(2.5, 0.2)),
      SmartBetXPremiumCandidate(fixtureId: 'a', simulation: run(1.0, 1.0)),
      SmartBetXPremiumCandidate(
        fixtureId: 'b',
        simulation: run(0.7, 0.7, dataQuality: 0.3),
      ),
    ];
    final ranked = const SmartBetXPremiumRanker().rank(
      selectedMatches: matches,
      minimumDrawProbability: 0.25,
      minimumDataQuality: 0.6,
    );
    expect(ranked.length, 3);
    expect(ranked.map((r) => r.candidate.fixtureId).toSet(), {'a', 'b', 'c'});
    expect(ranked.first.priority, isTrue);
    expect(ranked.skip(1).every((r) => !r.priority), isTrue);
  });

  test('X Premium rifiuta fixture duplicate', () {
    final fixture = SmartBetXPremiumCandidate(
      fixtureId: 'same',
      simulation: run(1, 1),
    );
    expect(
      () => const SmartBetXPremiumRanker().rank(
        selectedMatches: [fixture, fixture],
        minimumDrawProbability: 0.3,
        minimumDataQuality: 0.5,
      ),
      throwsArgumentError,
    );
  });
}
