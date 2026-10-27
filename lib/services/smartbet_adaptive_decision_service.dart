import 'smartbet_analysis_history_store.dart';
import 'smartbet_historical_calibration_service.dart';
import 'smartbet_learning_gate_service.dart';
import 'smartbet_shadow_outcome_service.dart';

enum SmartBetAdaptiveDecisionStatus {
  insufficientEvidence,
  calibrationUnavailable,
  unchanged,
  eligibleForTrial,
}

class SmartBetAdaptiveDecision {
  final SmartBetAnalysisEngine engine;
  final String market;

  final double originalProbability;
  final double shadowProbability;
  final double trialProbability;

  final int trainingSamples;
  final SmartBetAdaptiveDecisionStatus status;

  const SmartBetAdaptiveDecision({
    required this.engine,
    required this.market,
    required this.originalProbability,
    required this.shadowProbability,
    required this.trialProbability,
    required this.trainingSamples,
    required this.status,
  });

  /// P15A non modifica ancora le probabilita' live.
  double get liveProbability => originalProbability;

  bool get eligibleForTrial =>
      status == SmartBetAdaptiveDecisionStatus.eligibleForTrial;
}

class SmartBetAdaptiveDecisionService {
  const SmartBetAdaptiveDecisionService();

  SmartBetAdaptiveDecision evaluate({
    required SmartBetAnalysisEngine engine,
    required String market,
    required double probability,
    required DateTime asOf,
    required List<SmartBetAnalysisRecord> records,
    required SmartBetShadowOutcomeReport outcomes,
    int? fixtureId,
  }) {
    if (!probability.isFinite || probability < 0 || probability > 1) {
      throw ArgumentError.value(
        probability,
        'probability',
        'La probabilita deve essere compresa fra 0 e 1',
      );
    }

    final calibration = const SmartBetHistoricalCalibrationService().evaluate(
      engine: engine,
      market: market,
      probability: probability,
      asOf: asOf,
      records: records,
      fixtureId: fixtureId,
    );

    final gate = const SmartBetLearningGateService().evaluate(
      outcomes,
      asOf: asOf,
    );

    return decide(
      engine: engine,
      market: market,
      calibration: calibration,
      gate: gate,
    );
  }

  /// Risolve la decisione senza modificare le previsioni live.
  /// Separato da evaluate per consentire test deterministici.
  SmartBetAdaptiveDecision decide({
    required SmartBetAnalysisEngine engine,
    required String market,
    required SmartBetCalibrationResult calibration,
    required SmartBetLearningGateReport gate,
  }) {
    final normalizedMarket = normalizeAnalysisMarket(market);
    final original = calibration.original;
    final calibrated = calibration.calibrated;

    final matching = gate.decisions
        .where(
          (decision) =>
              decision.engine == engine.name &&
              decision.market == normalizedMarket,
        )
        .toList();

    final gateEligible =
        matching.length == 1 && matching.single.eligibleForTrial;

    final validCalibration =
        calibration.applied &&
        original.isFinite &&
        calibrated.isFinite &&
        original >= 0 &&
        original <= 1 &&
        calibrated >= 0 &&
        calibrated <= 1;

    final changed =
        validCalibration && (calibrated - original).abs() > 0.0000001;

    final status = !validCalibration
        ? SmartBetAdaptiveDecisionStatus.calibrationUnavailable
        : !gateEligible
        ? SmartBetAdaptiveDecisionStatus.insufficientEvidence
        : !changed
        ? SmartBetAdaptiveDecisionStatus.unchanged
        : SmartBetAdaptiveDecisionStatus.eligibleForTrial;

    final eligible = status == SmartBetAdaptiveDecisionStatus.eligibleForTrial;

    return SmartBetAdaptiveDecision(
      engine: engine,
      market: normalizedMarket,
      originalProbability: original,
      shadowProbability: validCalibration ? calibrated : original,
      trialProbability: eligible ? calibrated : original,
      trainingSamples: calibration.sampleSize,
      status: status,
    );
  }
}
