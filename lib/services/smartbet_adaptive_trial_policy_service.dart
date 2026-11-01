import 'smartbet_adaptive_decision_service.dart';
import 'smartbet_analysis_history_store.dart';

enum SmartBetTrialPolicyStatus {
  emergencyStop,
  candidateRejected,
  validationInsufficient,
  awaitingExplicitApproval,
  readyForShadowTrial,
}

/// Riepilogo da costruire in futuro a partire da esiti
/// prospettici verificati, mai da valori inseriti dall'utente.
class SmartBetTrialValidationEvidence {
  final SmartBetAnalysisEngine engine;
  final String market;
  final int prospectiveFixtures;
  final int distinctDays;
  final double overallBrierImprovement;
  final double earlyBrierImprovement;
  final double recentBrierImprovement;
  final DateTime firstPredictionAt;
  final DateTime lastResolvedAt;

  const SmartBetTrialValidationEvidence({
    required this.engine,
    required this.market,
    required this.prospectiveFixtures,
    required this.distinctDays,
    required this.overallBrierImprovement,
    required this.earlyBrierImprovement,
    required this.recentBrierImprovement,
    required this.firstPredictionAt,
    required this.lastResolvedAt,
  });
}

class SmartBetTrialPolicyDecision {
  final SmartBetTrialPolicyStatus status;
  final double originalProbability;
  final double shadowTrialProbability;

  const SmartBetTrialPolicyDecision({
    required this.status,
    required this.originalProbability,
    required this.shadowTrialProbability,
  });

  bool get readyForShadowTrial =>
      status == SmartBetTrialPolicyStatus.readyForShadowTrial;

  // Protezione obbligatoria: il servizio non abilita il live.
  double get liveProbability => originalProbability;
}

/// Politica sperimentale di autorizzazione.
/// Non salva dati, non modifica mercati, non effettua API call.
/// Il chiamante dovrà fornire prove realmente verificate.
class SmartBetAdaptiveTrialPolicyService {
  const SmartBetAdaptiveTrialPolicyService();

  static const int minimumProspectiveFixtures = 30;
  static const int minimumDistinctDays = 10;
  static const double maximumAdjustment = 0.10;
  static const double minimumOverallImprovement = 0.002;
  static const double minimumHalfImprovement = 0.001;

  SmartBetTrialPolicyDecision evaluate({
    required SmartBetAdaptiveDecision candidate,
    required DateTime asOf,
    SmartBetTrialValidationEvidence? evidence,
    bool explicitlyApproved = false,
    bool emergencyStopEnabled = true,
  }) {
    final original = candidate.originalProbability;
    final trial = candidate.trialProbability;

    SmartBetTrialPolicyDecision blocked(SmartBetTrialPolicyStatus status) {
      return SmartBetTrialPolicyDecision(
        status: status,
        originalProbability: original,
        shadowTrialProbability: original,
      );
    }

    if (emergencyStopEnabled) {
      return blocked(SmartBetTrialPolicyStatus.emergencyStop);
    }

    final delta = (trial - original).abs();
    final validCandidate =
        candidate.eligibleForTrial &&
        candidate.trainingSamples >= 50 &&
        normalizeAnalysisMarket(candidate.market).isNotEmpty &&
        original.isFinite &&
        trial.isFinite &&
        original >= 0 &&
        original <= 1 &&
        trial >= 0 &&
        trial <= 1 &&
        delta > 1e-7 &&
        delta <= maximumAdjustment + 1e-9;

    if (!validCandidate) {
      return blocked(SmartBetTrialPolicyStatus.candidateRejected);
    }

    final cutoff = asOf.toUtc();

    final validEvidence =
        evidence != null &&
        evidence.engine == candidate.engine &&
        normalizeAnalysisMarket(evidence.market) ==
            normalizeAnalysisMarket(candidate.market) &&
        evidence.prospectiveFixtures >= minimumProspectiveFixtures &&
        evidence.distinctDays >= minimumDistinctDays &&
        evidence.distinctDays <= evidence.prospectiveFixtures &&
        evidence.overallBrierImprovement.isFinite &&
        evidence.earlyBrierImprovement.isFinite &&
        evidence.recentBrierImprovement.isFinite &&
        evidence.overallBrierImprovement >= minimumOverallImprovement &&
        evidence.earlyBrierImprovement >= minimumHalfImprovement &&
        evidence.recentBrierImprovement >= minimumHalfImprovement &&
        evidence.firstPredictionAt.toUtc().isBefore(
          evidence.lastResolvedAt.toUtc(),
        ) &&
        evidence.lastResolvedAt.toUtc().isBefore(cutoff);

    if (!validEvidence) {
      return blocked(SmartBetTrialPolicyStatus.validationInsufficient);
    }

    if (!explicitlyApproved) {
      return blocked(SmartBetTrialPolicyStatus.awaitingExplicitApproval);
    }

    return SmartBetTrialPolicyDecision(
      status: SmartBetTrialPolicyStatus.readyForShadowTrial,
      originalProbability: original,
      shadowTrialProbability: trial,
    );
  }
}
