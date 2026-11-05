import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_shadow_service.dart';
import 'package:smartbet_ai_new/services/smartbet_match_simulation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_bridge_service.dart';

void main() {
  const bridge = SmartBetSimulationBridgeService();
  const simulator = SmartBetMatchSimulationService();

  SmartBetSimulationResult simulation() => simulator.simulate(
    const SmartBetMatchSimulationInput(
      expectedHomeGoals: 1.4,
      expectedAwayGoals: 1.1,
      dataQuality: 0.8,
    ),
  );

  test('confronto stesso xG: stessa probabilita e nessuna quota', () {
    final baseline = simulation();
    final report = bridge.compare(
      source: 'TEST',
      expectedHomeGoals: 1.4,
      expectedAwayGoals: 1.1,
      dataQuality: 0.8,
      existingProbabilities: {
        'X': baseline.draw,
        'OVER 2.5': baseline.probabilityFor('OVER 2.5'),
        'GOAL': baseline.probabilityFor('GOAL'),
      },
    );
    expect(report.dataQuality, 0.8);
    expect(report.comparedMarkets.length, 3);
    expect(report.mostDifferent.every((x) => x.absoluteDelta < 1e-12), isTrue);
    expect(report.unsupportedMarkets, isEmpty);
  });

  test('la X divergente viene riportata, non cambia la previsione vecchia', () {
    final old = <String, double>{'X': 0.1};
    final report = bridge.compare(
      source: 'TEST',
      expectedHomeGoals: 1.4,
      expectedAwayGoals: 1.1,
      dataQuality: 1,
      existingProbabilities: old,
    );
    expect(report.comparedMarkets.single.delta, greaterThan(0));
    expect(old['X'], 0.1);
    expect(report.existingProbabilities['X'], 0.1);
  });

  test('mercato non supportato dichiarato, non interpretato come zero', () {
    final report = bridge.compare(
      source: 'TEST',
      expectedHomeGoals: 1.4,
      expectedAwayGoals: 1.1,
      dataQuality: 1,
      existingProbabilities: {'MERCATO SCONOSCIUTO': 0.72},
    );
    expect(report.comparedMarkets, isEmpty);
    expect(report.unsupportedMarkets, ['MERCATO SCONOSCIUTO']);
  });

  test('mercati estesi e combo: equivalenza con griglia punteggi', () {
    final r = simulation();
    final candidates = <String, bool Function(int, int)>{
      'CASA 2+ GOL': (h, a) => h >= 2,
      'OSPITE 3+ GOL': (h, a) => a >= 3,
      'GOAL + O2.5': (h, a) => h > 0 && a > 0 && h + a >= 3,
      'NO GOAL + U2.5': (h, a) => (h == 0 || a == 0) && h + a <= 2,
      '1X + O2.5': (h, a) => h >= a && h + a >= 3,
      'X2 + U3.5': (h, a) => a >= h && h + a <= 3,
      '1 + O1.5': (h, a) => h > a && h + a >= 2,
    };
    for (final entry in candidates.entries) {
      final expected = r.exactScores
          .where((s) => entry.value(s.homeGoals, s.awayGoals))
          .fold<double>(0, (p, s) => p + s.probability);
      expect(
        SmartBetSimulationMarketAdapter.forMarket(r, entry.key),
        closeTo(expected, 1e-12),
        reason: entry.key,
      );
    }
    expect(
      SmartBetSimulationMarketAdapter.forMarket(r, 'CASA SEGNA'),
      closeTo(r.probabilityFor('HOME SCORES'), 1e-12),
    );
  });

  test('primo gol coerente in modello indipendente', () {
    final r = simulation();
    final home = SmartBetSimulationMarketAdapter.forMarket(
      r,
      'CASA SEGNA PRIMA',
    )!;
    final away = SmartBetSimulationMarketAdapter.forMarket(
      r,
      'OSPITE SEGNA PRIMA',
    )!;
    expect(home + away, closeTo(1 - r.exactScoreProbability(0, 0), 1e-10));
  });

  test('nessun primo gol spurio con intensita condivisa', () {
    final r = simulator.simulate(
      const SmartBetMatchSimulationInput(
        expectedHomeGoals: 1.4,
        expectedAwayGoals: 1.1,
        sharedGoalIntensity: 0.2,
        dataQuality: 1,
      ),
    );
    expect(
      SmartBetSimulationMarketAdapter.forMarket(r, 'CASA SEGNA PRIMA'),
      isNull,
    );
  });

  test('input non validi bloccati senza creare report', () {
    expect(
      () => bridge.compare(
        source: 'TEST',
        expectedHomeGoals: 1.4,
        expectedAwayGoals: 1.1,
        dataQuality: 1,
        existingProbabilities: {'X': 55},
      ),
      throwsArgumentError,
    );
    expect(
      () => bridge.compare(
        source: 'TEST',
        expectedHomeGoals: 1.4,
        expectedAwayGoals: 1.1,
        dataQuality: 1,
        existingProbabilities: {'x': 0.2, 'X': 0.3},
      ),
      throwsArgumentError,
    );
  });

  test('snapshot GoalVdLine: percentuali convertite correttamente', () {
    final snapshot = GoalVdLineShadowSnapshot(
      fixtureId: 123,
      homeTeam: 'A',
      awayTeam: 'B',
      prediction: 'X',
      homeProbability: 34,
      drawProbability: 32,
      awayProbability: 34,
      over15Probability: 60,
      over25Probability: 40,
      over35Probability: 20,
      goalProbability: 51,
      expectedHomeGoals: 1.4,
      expectedAwayGoals: 1.1,
      dataConfidence: 80,
      predictionConfidence: 60,
      simulations: 20000,
      capturedAt: DateTime.utc(2026, 11, 1),
    );
    final report = bridge.fromGoalVdLineShadow(
      snapshot: snapshot,
      dataQuality: 0.8,
    );
    expect(report.source, 'GOALVDLINE_SHADOW');
    expect(report.fixtureId, '123');
    expect(report.existingProbabilities['X'], 0.32);
    expect(report.comparedMarkets.length, 7);
  });
}
