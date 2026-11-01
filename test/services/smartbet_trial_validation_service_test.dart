import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_adaptive_decision_service.dart';
import 'package:smartbet_ai_new/services/smartbet_adaptive_trial_policy_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';
import 'package:smartbet_ai_new/services/smartbet_trial_validation_service.dart';

void main() {
  const validator = SmartBetTrialValidationService();
  const policy = SmartBetAdaptiveTrialPolicyService();

  final asOf = DateTime.utc(2026, 11, 1);
  final validationStart = DateTime.utc(2026, 9, 1);

  SmartBetShadowOutcomeCase sample(
    int fixtureId, {
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    String market = 'GOAL',
    bool correct = false,
    bool qualified = true,
    bool calibrationApplied = true,
    bool resolvedInFuture = false,
    bool latePrediction = false,
  }) {
    final kickoff = DateTime.utc(
      2026,
      10,
      1,
      18,
    ).add(Duration(days: fixtureId ~/ 2));

    final predictedAt = latePrediction
        ? kickoff.add(const Duration(hours: 1))
        : kickoff.subtract(const Duration(hours: 12));

    final resolvedAt = resolvedInFuture
        ? asOf.add(const Duration(days: 2))
        : kickoff.add(const Duration(hours: 4));

    final record = SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId + 1000,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Test',
      country: 'Test',
      matchDate: kickoff,
      market: market,
      probability: 0.80,
      smartScore: engine == SmartBetAnalysisEngine.smartBet ? 80 : null,
      confidence: null,
      classification: null,
      qualified: engine == SmartBetAnalysisEngine.diego ? qualified : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 2,
      actualAwayGoals: correct ? 1 : 0,
      firstSeenAt: predictedAt,
      lastSeenAt: resolvedAt,
      resolvedAt: resolvedAt,
    );

    final prediction = SmartBetShadowPrediction(
      key: record.key,
      engine: engine.name,
      market: market,
      fixtureId: record.fixtureId,
      predictedAt: predictedAt,
      originalProbability: 0.80,
      calibratedProbability: 0.74,
      trainingSampleSize: 150,
      calibrationApplied: calibrationApplied,
    );

    return SmartBetShadowOutcomeCase(record: record, prediction: prediction);
  }

  List<SmartBetShadowOutcomeCase> dataset() {
    return [for (var i = 0; i < 30; i++) sample(i, correct: i.isOdd)];
  }

  test('30 partite su 15 giorni producono evidenza', () {
    final result = validator.evaluate(
      cases: dataset(),
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      validationStartsAt: validationStart,
      asOf: asOf,
    );

    expect(result, isNotNull);
    expect(result!.prospectiveFixtures, 30);
    expect(result.distinctDays, 15);
    expect(result.overallBrierImprovement, greaterThan(0));
    expect(result.earlyBrierImprovement, greaterThan(0));
    expect(result.recentBrierImprovement, greaterThan(0));
  });

  test('motori e mercati diversi non si mescolano', () {
    final result = validator.evaluate(
      cases: [
        sample(0),
        sample(1, engine: SmartBetAnalysisEngine.diego),
        sample(2, market: 'OVER 2.5'),
      ],
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      validationStartsAt: validationStart,
      asOf: asOf,
    );

    expect(result!.prospectiveFixtures, 1);
  });

  test('risultati futuri e previsioni tardive esclusi', () {
    final result = validator.evaluate(
      cases: [
        sample(0, resolvedInFuture: true),
        sample(1, latePrediction: true),
      ],
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      validationStartsAt: validationStart,
      asOf: asOf,
    );

    expect(result, isNull);
  });

  test('duplicati e calibrazioni non disponibili esclusi', () {
    final first = sample(0);
    final result = validator.evaluate(
      cases: [first, first, sample(1, calibrationApplied: false)],
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      validationStartsAt: validationStart,
      asOf: asOf,
    );

    expect(result!.prospectiveFixtures, 1);
  });

  test('Diego non qualificato escluso', () {
    final result = validator.evaluate(
      cases: [
        sample(0, engine: SmartBetAnalysisEngine.diego, qualified: false),
      ],
      engine: SmartBetAnalysisEngine.diego,
      market: 'GOAL',
      validationStartsAt: validationStart,
      asOf: asOf,
    );

    expect(result, isNull);
  });

  test('policy autorizza solo shadow e lascia live originale', () {
    final evidence = validator.evaluate(
      cases: dataset(),
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      validationStartsAt: validationStart,
      asOf: asOf,
    );

    final candidate = SmartBetAdaptiveDecision(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      originalProbability: 0.80,
      shadowProbability: 0.74,
      trialProbability: 0.74,
      trainingSamples: 150,
      status: SmartBetAdaptiveDecisionStatus.eligibleForTrial,
    );

    final decision = policy.evaluate(
      candidate: candidate,
      asOf: asOf,
      evidence: evidence,
      explicitlyApproved: true,
      emergencyStopEnabled: false,
    );

    expect(decision.status, SmartBetTrialPolicyStatus.readyForShadowTrial);
    expect(decision.shadowTrialProbability, 0.74);
    expect(decision.liveProbability, 0.80);
  });
}
