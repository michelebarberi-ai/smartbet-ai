import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_match_simulation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_audit_service.dart';

void main() {
  const engine = SmartBetMatchSimulationService();
  const audit = SmartBetSimulationAuditService();

  SmartBetSimulationCompletedFixture complete(String id, int h, int a) =>
      SmartBetSimulationCompletedFixture(
        fixtureId: id,
        preMatchPrediction: engine.simulate(
          const SmartBetMatchSimulationInput(
            expectedHomeGoals: 1.3,
            expectedAwayGoals: 0.9,
            dataQuality: 1,
          ),
        ),
        finalHomeGoals: h,
        finalAwayGoals: a,
      );

  test('misura X e mercati alternativi anche se non selezionati', () {
    final result = audit.summarize([complete('100', 1, 1)]);
    expect(result['X']!.observedFrequency, 1);
    expect(result['OVER 2.5']!.observedFrequency, 0);
    expect(result['UNDER 4.5']!.observedFrequency, 1);
    expect(result['GOAL']!.observedFrequency, 1);
    expect(result['1X']!.observedFrequency, 1);
    expect(result['MULTIGOL 2-4']!.observedFrequency, 1);
  });

  test('frequenza osservata e Brier sono calcolati correttamente', () {
    final result = audit.summarize([complete('1', 0, 0), complete('2', 0, 2)]);
    final x = result['X']!;
    expect(x.sampleSize, 2);
    expect(x.observedFrequency, 0.5);
    final predicted = complete(
      '3',
      0,
      0,
    ).preMatchPrediction.probabilityFor('X');
    expect(x.meanPredictedProbability, closeTo(predicted, 1e-12));
    expect(
      x.brierScore,
      closeTo(
        ((predicted - 1) * (predicted - 1) + predicted * predicted) / 2,
        1e-12,
      ),
    );
  });

  test('partite duplicate non vengono conteggiate due volte', () {
    expect(
      () => audit.summarize([complete('1', 1, 1), complete('1', 1, 1)]),
      throwsArgumentError,
    );
  });

  test('nessun dato: nessuna statistica inventata', () {
    expect(audit.summarize([]), isEmpty);
  });

  test('risultato non valido bloccato', () {
    expect(
      () => audit.summarize([complete('err', -1, 1)]),
      throwsArgumentError,
    );
  });
}
