import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_daily_learning_choice_service.dart';
import 'package:smartbet_ai_new/services/smartbet_live_calibration_service.dart';
import 'package:smartbet_ai_new/services/smartbet_learning_gate_service.dart';

final _emptyGate = SmartBetLiveCalibrationSession(
  enabled: true,
  emergencyStop: false,
  startedAt: DateTime.utc(2026, 11, 2),
  history: const [],
  gate: const SmartBetLearningGateReport(decisions: []),
);

void main() {
  test('consenso OFF: probabilita e storico restano originali', () {
    final result = SmartBetDailyLearningChoiceService.evaluate(
      session: null, market: 'OVER 2.5', fixtureId: 123,
      originalPercent: 70, odd: 1.8,
    );
    expect(result.applied, isFalse);
    expect(result.originalPercent, 70);
    expect(result.percent, 70);
    expect(result.expectedValue, closeTo(0.26, 0.00001));
  });

  test('consenso ON ma gate non validato: nessuna correzione', () {
    final result = SmartBetDailyLearningChoiceService.evaluate(
      session: _emptyGate, market: 'GOAL', fixtureId: 123,
      originalPercent: 65, odd: 1.5,
    );
    expect(result.percent, 65);
    expect(result.samples, 0);
    expect(result.applied, isFalse);
  });

  test('assenza di quota reale: fail closed', () {
    final result = SmartBetDailyLearningChoiceService.evaluate(
      session: _emptyGate, market: 'GOAL', fixtureId: 123,
      originalPercent: 65, odd: 1.1,
    );
    expect(result.percent, 65);
    expect(result.edge, 0);
    expect(result.expectedValue, 0);
  });

  test('B62: quotazioni 1.21-1.24 usano soglia condivisa anche nel learning', () {
    for (final odd in [1.21, 1.24, 1.25]) {
      final result = SmartBetDailyLearningChoiceService.evaluate(
        session: _emptyGate,
        market: 'GOAL',
        fixtureId: 123,
        originalPercent: 75,
        odd: odd,
      );
      expect(result.percent, 75); // Gate non validato: nessuna correzione.
      expect(result.edge, closeTo(0.75 - 1.0 / odd, 0.000001));
      expect(result.expectedValue, closeTo(0.75 * odd - 1.0, 0.000001));
    }
    for (final odd in [1.19, 1.20, double.nan, double.infinity]) {
      final result = SmartBetDailyLearningChoiceService.evaluate(
        session: _emptyGate,
        market: 'GOAL',
        fixtureId: 123,
        originalPercent: 75,
        odd: odd,
      );
      expect(result.edge, 0.0);
      expect(result.expectedValue, 0.0);
      expect(result.applied, isFalse);
    }
  });

  test('mercati rimborsabili non calibrati', () {
    final result = SmartBetDailyLearningChoiceService.evaluate(
      session: _emptyGate, market: 'DNB CASA', fixtureId: 123,
      originalPercent: 70, odd: 1.8,
    );
    expect(result.applied, isFalse);
    expect(result.percent, 70);
  });

  test('probabilita implicita e valore atteso coerenti con il mercato', () {
    final result = SmartBetDailyLearningChoiceService.evaluate(
      session: null, market: '1X', fixtureId: 123,
      originalPercent: 60, odd: 2.0,
    );
    expect(result.edge, closeTo(0.10, 0.00001));
    expect(result.expectedValue, closeTo(0.20, 0.00001));
  });
}
