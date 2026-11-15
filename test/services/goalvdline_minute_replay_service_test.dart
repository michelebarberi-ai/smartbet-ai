import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_minute_replay_service.dart';
import 'package:smartbet_ai_new/services/smartbet_match_simulation_service.dart';

void main() {
  const replay = GoalVdLineMinuteReplayService();
  const baseline = SmartBetMatchSimulationService();

  GoalVdLineMinuteReplayReport run({
    int fixtureId = 4173,
    double home = 1.65,
    double away = 1.10,
    int trials = 12000,
  }) => replay.simulate(
    fixtureId: fixtureId,
    expectedHomeGoals: home,
    expectedAwayGoals: away,
    simulations: trials,
  );

  test('B53: la stessa fixture e gli stessi xG producono lo stesso replay', () {
    final first = run();
    final second = run();
    expect(first.toJson(), second.toJson());
    expect(first.simulations, 12000);
    expect(first.toJson()['mode'], 'shadow_only');
    expect(first.toJson()['scope'], 'timed_goals_only');
  });

  test('B53: il replay conta tutti i gol e li colloca tra 1 e 90', () {
    final result = run();
    var home = 0;
    var away = 0;
    var minute = 1;
    var halfHome = 0;
    var halfAway = 0;
    for (final goal in result.illustrativeGoals) {
      expect(goal.minute, inInclusiveRange(1, 90));
      expect(goal.minute, greaterThanOrEqualTo(minute));
      minute = goal.minute;
      if (goal.homeTeam) {
        home++;
        if (goal.minute <= 45) halfHome++;
      } else {
        away++;
        if (goal.minute <= 45) halfAway++;
      }
      expect(goal.homeScore, home);
      expect(goal.awayScore, away);
    }
    expect(result.fulltimeHome, home);
    expect(result.fulltimeAway, away);
    expect(result.halftimeHome, halfHome);
    expect(result.halftimeAway, halfAway);
  });

  test('B53: 1X2, doppie chance, Goal e Over restano coerenti', () {
    final p = run().probabilities;
    expect(p['1']! + p['X']! + p['2']!, closeTo(1, 1e-12));
    expect(p['1X'], closeTo(p['1']! + p['X']!, 1e-12));
    expect(p['X2'], closeTo(p['X']! + p['2']!, 1e-12));
    expect(p['12'], closeTo(p['1']! + p['2']!, 1e-12));
    expect(p['GOAL']! + p['NO GOAL']!, closeTo(1, 1e-12));
    expect(p['OVER 1.5']! + p['UNDER 1.5']!, closeTo(1, 1e-12));
    expect(p['OVER 2.5']! + p['UNDER 2.5']!, closeTo(1, 1e-12));
    expect(p['OVER 1.5'], greaterThanOrEqualTo(p['OVER 2.5']!));
    expect(p['GOAL'], lessThanOrEqualTo(p['OVER 1.5']!));
    for (final value in p.values) {
      expect(value, inInclusiveRange(0, 1));
    }
  });

  test('B53: replay Poisson dei gol concorda con il modello esatto', () {
    final report = run(trials: 20000);
    final exact = baseline.simulate(const SmartBetMatchSimulationInput(
      expectedHomeGoals: 1.65,
      expectedAwayGoals: 1.10,
      dataQuality: 0.8,
    ));
    for (final market in [
      '1', 'X', '2', 'GOAL', 'OVER 1.5', 'OVER 2.5',
    ]) {
      expect(
        report.probabilities[market],
        closeTo(exact.probabilityFor(market), 0.03),
        reason: '$market: i due motori devono avere lo stesso processo '
            'di gol attesi ma campionamenti diversi',
      );
    }
    expect(report.topExactScores.length, lessThanOrEqualTo(5));
    expect(
      report.topExactScores.values.every((v) => v > 0 && v <= 1),
      isTrue,
    );
  });

  test('B53: rifiuta xG mancanti, NaN e numerosità irragionevoli', () {
    expect(() => run(fixtureId: 0), throwsArgumentError);
    expect(() => run(home: 0), throwsArgumentError);
    expect(() => run(away: 0), throwsArgumentError);
    expect(() => run(home: double.nan), throwsArgumentError);
    expect(() => run(away: double.infinity), throwsArgumentError);
    expect(() => run(home: 7), throwsArgumentError);
    expect(() => run(trials: 999), throwsArgumentError);
    expect(() => run(trials: 100001), throwsArgumentError);
  });

  test('B53: la demo non contiene quote o eventi tattici inventati', () {
    final json = run().toJson();
    final limitations = (json['limitations'] as List).cast<String>();
    expect(limitations, contains(contains('Nessun tiro')));
    expect(json.containsKey('bookmaker'), isFalse);
    expect(json.containsKey('odd'), isFalse);
    expect((json['illustrativeReplay'] as Map)['goals'], isA<List>());
  });
}
