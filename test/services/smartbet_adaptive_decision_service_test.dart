import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_adaptive_decision_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_historical_calibration_service.dart';
import 'package:smartbet_ai_new/services/smartbet_learning_gate_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';

void main() {
  const service = SmartBetAdaptiveDecisionService();

  SmartBetCalibrationResult calibration({
    bool applied = true,
    double original = 0.80,
    double calibrated = 0.72,
  }) {
    return SmartBetCalibrationResult(
      original: original,
      calibrated: calibrated,
      sampleSize: 150,
      historicalGap: calibrated - original,
      applied: applied,
    );
  }

  SmartBetLearningGateReport gate({
    bool eligible = true,
    String market = 'GOAL',
  }) {
    return SmartBetLearningGateReport(
      decisions: [
        SmartBetLearningGateDecision(
          engine: SmartBetAnalysisEngine.smartBet.name,
          market: market,
          adjustedSamples: 150,
          distinctDays: 30,
          overallImprovement: 0.01,
          earlyImprovement: 0.01,
          recentImprovement: 0.01,
          status: eligible
              ? SmartBetLearningGateStatus.eligibleForTrial
              : SmartBetLearningGateStatus.insufficientData,
        ),
      ],
    );
  }

  test('gate e calibrazione validi: candidato al trial', () {
    final result = service.decide(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      calibration: calibration(),
      gate: gate(),
    );

    expect(result.eligibleForTrial, true);
    expect(result.originalProbability, 0.80);
    expect(result.shadowProbability, 0.72);
    expect(result.trialProbability, 0.72);
    expect(result.liveProbability, 0.80);
  });

  test('gate non valido: correzione non autorizzata', () {
    final result = service.decide(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      calibration: calibration(),
      gate: gate(eligible: false),
    );

    expect(result.eligibleForTrial, false);
    expect(result.trialProbability, 0.80);
    expect(result.liveProbability, 0.80);
  });

  test('calibrazione non disponibile: nessuna modifica', () {
    final result = service.decide(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      calibration: calibration(applied: false),
      gate: gate(),
    );

    expect(result.eligibleForTrial, false);
    expect(result.shadowProbability, 0.80);
    expect(result.liveProbability, 0.80);
  });

  test('mercato diverso: gate non autorizza', () {
    final result = service.decide(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      calibration: calibration(),
      gate: gate(market: 'UNDER 2.5'),
    );

    expect(result.eligibleForTrial, false);
    expect(result.trialProbability, 0.80);
  });

  test('assenza di storico: nessun apprendimento', () {
    final outcomes = SmartBetShadowOutcomeReport(
      cases: const [],
      overall: SmartBetShadowOutcomeSummary.fromCases(const []),
      byEngine: const {},
      byMarket: const {},
    );

    final result = service.evaluate(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.80,
      asOf: DateTime.utc(2026, 10, 27),
      records: const [],
      outcomes: outcomes,
      fixtureId: 123,
    );

    expect(result.eligibleForTrial, false);
    expect(result.trainingSamples, 0);
    expect(result.liveProbability, 0.80);
  });
}
