import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_adaptive_decision_service.dart';
import 'package:smartbet_ai_new/services/smartbet_adaptive_trial_policy_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  const policy = SmartBetAdaptiveTrialPolicyService();
  final now = DateTime.utc(2026, 11, 1);

  SmartBetAdaptiveDecision candidate({
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
    double original = 0.80,
    double trial = 0.74,
    int samples = 150,
    bool eligible = true,
  }) {
    return SmartBetAdaptiveDecision(
      engine: engine,
      market: market,
      originalProbability: original,
      shadowProbability: trial,
      trialProbability: trial,
      trainingSamples: samples,
      status: eligible
          ? SmartBetAdaptiveDecisionStatus.eligibleForTrial
          : SmartBetAdaptiveDecisionStatus.insufficientEvidence,
    );
  }

  SmartBetTrialValidationEvidence evidence({
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
    int fixtures = 40,
    int days = 15,
    double overall = 0.008,
    double early = 0.005,
    double recent = 0.010,
    DateTime? resolvedAt,
  }) {
    return SmartBetTrialValidationEvidence(
      engine: engine,
      market: market,
      prospectiveFixtures: fixtures,
      distinctDays: days,
      overallBrierImprovement: overall,
      earlyBrierImprovement: early,
      recentBrierImprovement: recent,
      firstPredictionAt: DateTime.utc(2026, 9, 1),
      lastResolvedAt: resolvedAt ?? DateTime.utc(2026, 10, 30),
    );
  }

  test('interruttore di emergenza attivo per default', () {
    final result = policy.evaluate(
      candidate: candidate(),
      asOf: now,
      evidence: evidence(),
      explicitlyApproved: true,
    );
    expect(result.status, SmartBetTrialPolicyStatus.emergencyStop);
    expect(result.liveProbability, 0.80);
  });

  test('gate insufficiente blocca anche con autorizzazione', () {
    final result = policy.evaluate(
      candidate: candidate(eligible: false),
      asOf: now,
      evidence: evidence(),
      explicitlyApproved: true,
      emergencyStopEnabled: false,
    );
    expect(result.status, SmartBetTrialPolicyStatus.candidateRejected);
  });

  test('campione insufficiente non autorizza il trial', () {
    final result = policy.evaluate(
      candidate: candidate(),
      asOf: now,
      evidence: evidence(fixtures: 12),
      explicitlyApproved: true,
      emergencyStopEnabled: false,
    );
    expect(result.status, SmartBetTrialPolicyStatus.validationInsufficient);
  });

  test('risultati conosciuti solo nel futuro vengono esclusi', () {
    final result = policy.evaluate(
      candidate: candidate(),
      asOf: now,
      evidence: evidence(resolvedAt: DateTime.utc(2026, 11, 3)),
      explicitlyApproved: true,
      emergencyStopEnabled: false,
    );
    expect(result.status, SmartBetTrialPolicyStatus.validationInsufficient);
  });

  test('validazione di Diego non autorizza SmartBet', () {
    final result = policy.evaluate(
      candidate: candidate(),
      asOf: now,
      evidence: evidence(engine: SmartBetAnalysisEngine.diego),
      explicitlyApproved: true,
      emergencyStopEnabled: false,
    );
    expect(result.status, SmartBetTrialPolicyStatus.validationInsufficient);
  });

  test('miglioramento incoerente non autorizza il trial', () {
    final result = policy.evaluate(
      candidate: candidate(),
      asOf: now,
      evidence: evidence(recent: -0.003),
      explicitlyApproved: true,
      emergencyStopEnabled: false,
    );
    expect(result.status, SmartBetTrialPolicyStatus.validationInsufficient);
  });

  test('anche il candidato autorizzato resta fuori dal live', () {
    final pending = policy.evaluate(
      candidate: candidate(),
      asOf: now,
      evidence: evidence(),
      emergencyStopEnabled: false,
    );
    expect(pending.status, SmartBetTrialPolicyStatus.awaitingExplicitApproval);

    final approved = policy.evaluate(
      candidate: candidate(),
      asOf: now,
      evidence: evidence(),
      explicitlyApproved: true,
      emergencyStopEnabled: false,
    );
    expect(approved.status, SmartBetTrialPolicyStatus.readyForShadowTrial);
    expect(approved.shadowTrialProbability, 0.74);
    expect(approved.liveProbability, 0.80);
  });
}
