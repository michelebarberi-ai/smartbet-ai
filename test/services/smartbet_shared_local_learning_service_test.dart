import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_live_calibration_service.dart';
import 'package:smartbet_ai_new/services/smartbet_learning_gate_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shared_local_learning_service.dart';

void main() {
  final noGate = SmartBetLiveCalibrationSession(
    enabled: true,
    emergencyStop: false,
    startedAt: _date,
    history: [],
    gate: SmartBetLearningGateReport(decisions: []),
  );

  test('OFF: la probabilità resta originale', () {
    final result = SmartBetSharedLocalLearningService.evaluate(
      session: null,
      market: 'OVER 2.5',
      originalPercent: 72,
      fixtureId: 101,
      hasRealOdd: true,
    );
    expect(result.percent, 72);
    expect(result.originalPercent, 72);
    expect(result.applied, isFalse);
  });

  test('ON ma nessun gate: non corregge', () {
    final result = SmartBetSharedLocalLearningService.evaluate(
      session: noGate,
      market: 'GOAL',
      originalPercent: 63,
      fixtureId: 101,
      hasRealOdd: true,
    );
    expect(result.percent, 63);
    expect(result.applied, isFalse);
  });

  test('assenza quota reale: non corregge', () {
    final result = SmartBetSharedLocalLearningService.evaluate(
      session: noGate,
      market: 'GOAL',
      originalPercent: 63,
      fixtureId: 101,
      hasRealOdd: false,
    );
    expect(result.percent, 63);
  });

  test('non calibra mercati rimborsabili o non-binari', () {
    for (final market in [
      'DNB CASA',
      'HCP ASIA CASA -0.5',
      'HCP EURO CASA -2 2',
      'COMBO CHANCE',
    ]) {
      final result = SmartBetSharedLocalLearningService.evaluate(
        session: noGate,
        market: market,
        originalPercent: 74,
        fixtureId: 101,
        hasRealOdd: true,
      );
      expect(result.percent, 74);
      expect(result.applied, isFalse);
    }
  });

  test('input non valido: non corregge', () {
    for (final probability in [-1, 101]) {
      final result = SmartBetSharedLocalLearningService.evaluate(
        session: noGate,
        market: 'OVER 2.5',
        originalPercent: probability,
        fixtureId: 101,
        hasRealOdd: true,
      );
      expect(result.percent, probability);
    }
  });
}

final DateTime _date = DateTime.utc(2026, 11, 2);
