import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_learning_gate_service.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_learning_store.dart';
import 'package:smartbet_ai_new/services/smartbet_shadow_outcome_service.dart';

void main() {
  const gate = SmartBetLearningGateService();

  SmartBetShadowOutcomeReport report({
    required int count,
    required bool Function(int index) correct,
    double calibrated = 0.70,
  }) {
    final cases = <SmartBetShadowOutcomeCase>[];

    for (var i = 0; i < count; i++) {
      final predictedAt = DateTime.utc(2026, 1, 1).add(Duration(days: i));
      final matchDate = predictedAt.add(const Duration(days: 1));
      final resolvedAt = predictedAt.add(const Duration(days: 2));

      final record = SmartBetAnalysisRecord(
        engine: SmartBetAnalysisEngine.smartBet,
        fixtureId: i + 1,
        homeTeam: 'Home',
        awayTeam: 'Away',
        league: 'Serie A',
        country: 'Italy',
        matchDate: matchDate,
        market: 'GOAL',
        probability: 0.80,
        smartScore: 70,
        confidence: null,
        classification: null,
        qualified: null,
        sources: const [SmartBetAnalysisSource.analysis],
        prospectiveEligible: true,
        status: correct(i)
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong,
        actualHomeGoals: 2,
        actualAwayGoals: 1,
        firstSeenAt: predictedAt,
        lastSeenAt: resolvedAt,
        resolvedAt: resolvedAt,
      );

      final prediction = SmartBetShadowPrediction(
        key: record.key,
        engine: record.engine.name,
        market: record.market,
        fixtureId: record.fixtureId,
        predictedAt: predictedAt,
        originalProbability: 0.80,
        calibratedProbability: calibrated,
        trainingSampleSize: 50,
        calibrationApplied: true,
      );

      cases.add(
        SmartBetShadowOutcomeCase(record: record, prediction: prediction),
      );
    }

    return SmartBetShadowOutcomeReport(
      cases: cases,
      overall: SmartBetShadowOutcomeSummary.fromCases(cases),
      byEngine: const {},
      byMarket: const {},
    );
  }

  test('senza dati non autorizza nulla', () {
    final result = gate.evaluate(
      report(count: 0, correct: (_) => false),
      asOf: DateTime.utc(2027, 1, 1),
    );

    expect(result.eligibleMarkets, 0);
    expect(result.decisions, isEmpty);
  });

  test('campione insufficiente resta bloccato', () {
    final result = gate.evaluate(
      report(count: 99, correct: (_) => false),
      asOf: DateTime.utc(2027, 1, 1),
    );

    expect(result.eligibleMarkets, 0);
    expect(
      result.decisions.single.status,
      SmartBetLearningGateStatus.insufficientData,
    );
  });

  test('miglioramento stabile rende idoneo al trial', () {
    final result = gate.evaluate(
      report(count: 120, correct: (_) => false),
      asOf: DateTime.utc(2027, 1, 1),
    );

    final decision = result.decisions.single;

    expect(decision.adjustedSamples, 120);
    expect(decision.eligibleForTrial, true);
    expect(result.eligibleMarkets, 1);
  });

  test('peggioramento recente blocca il trial', () {
    final result = gate.evaluate(
      report(count: 120, correct: (index) => index >= 60),
      asOf: DateTime.utc(2027, 1, 1),
    );

    final decision = result.decisions.single;

    expect(decision.overallImprovement, greaterThan(0));
    expect(decision.recentImprovement, lessThan(0));
    expect(decision.eligibleForTrial, false);
    expect(decision.status, SmartBetLearningGateStatus.inconsistentImprovement);
  });

  test('non usa risultati futuri o disponibili al cutoff', () {
    final evidence = report(count: 120, correct: (_) => false);

    final early = gate.evaluate(evidence, asOf: DateTime.utc(2026, 3, 1));

    expect(early.eligibleMarkets, 0);
    expect(early.decisions, isNotEmpty);
    expect(early.decisions.single.adjustedSamples, lessThan(100));
    expect(
      early.decisions.single.status,
      SmartBetLearningGateStatus.insufficientData,
    );

    final boundary = gate.evaluate(evidence, asOf: DateTime.utc(2026, 1, 3));

    expect(boundary.eligibleMarkets, 0);
    expect(boundary.decisions, isEmpty);
  });

  test('correzione dannosa viene bloccata', () {
    final result = gate.evaluate(
      report(count: 120, correct: (_) => true),
      asOf: DateTime.utc(2027, 1, 1),
    );

    expect(result.eligibleMarkets, 0);
    expect(
      result.decisions.single.status,
      SmartBetLearningGateStatus.inconsistentImprovement,
    );
  });
}
