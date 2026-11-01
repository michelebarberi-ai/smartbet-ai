import 'smartbet_adaptive_trial_policy_service.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_shadow_outcome_service.dart';

/// Costruisce evidenze cronologiche da snapshot già registrati.
/// Non legge API e non modifica alcun dato persistito.
class SmartBetTrialValidationService {
  const SmartBetTrialValidationService();

  SmartBetTrialValidationEvidence? evaluate({
    required Iterable<SmartBetShadowOutcomeCase> cases,
    required SmartBetAnalysisEngine engine,
    required String market,
    required DateTime validationStartsAt,
    required DateTime asOf,
  }) {
    final start = validationStartsAt.toUtc();
    final cutoff = asOf.toUtc();
    final normalizedMarket = normalizeAnalysisMarket(market);

    if (!start.isBefore(cutoff) || normalizedMarket.isEmpty) {
      return null;
    }

    final valid = <SmartBetShadowOutcomeCase>[];

    for (final item in cases) {
      final record = item.record;
      final snapshot = item.prediction;
      final kickoff = record.matchDate.toUtc();
      final predictedAt = snapshot.predictedAt.toUtc();
      final resolvedAt = record.resolvedAt?.toUtc();
      final original = snapshot.originalProbability;
      final calibrated = snapshot.calibratedProbability;
      final stored = record.probability;

      if (record.engine != engine ||
          normalizeAnalysisMarket(record.market) != normalizedMarket ||
          snapshot.engine != engine.name ||
          normalizeAnalysisMarket(snapshot.market) != normalizedMarket ||
          snapshot.key != record.key ||
          snapshot.fixtureId != record.fixtureId ||
          record.fixtureId <= 0 ||
          !record.prospectiveEligible ||
          !record.hasActualResult ||
          record.asianSettlement != null ||
          !snapshot.calibrationApplied ||
          snapshot.trainingSampleSize < 50 ||
          stored == null ||
          !stored.isFinite ||
          !original.isFinite ||
          !calibrated.isFinite ||
          stored < 0 ||
          stored > 1 ||
          original < 0 ||
          original > 1 ||
          calibrated < 0 ||
          calibrated > 1 ||
          (stored - original).abs() > 1e-9 ||
          (calibrated - original).abs() <= 1e-9 ||
          (calibrated - original).abs() > 0.100000001 ||
          !record.firstSeenAt.toUtc().isAtSameMomentAs(predictedAt) ||
          !predictedAt.isAfter(start) ||
          !predictedAt.isBefore(kickoff) ||
          resolvedAt == null ||
          !resolvedAt.isAfter(kickoff) ||
          !resolvedAt.isBefore(cutoff) ||
          (record.status != SmartBetAnalysisStatus.correct &&
              record.status != SmartBetAnalysisStatus.wrong)) {
        continue;
      }

      if (engine == SmartBetAnalysisEngine.diego && record.qualified != true) {
        continue;
      }

      valid.add(item);
    }

    valid.sort((a, b) {
      final time = a.prediction.predictedAt.compareTo(b.prediction.predictedAt);
      if (time != 0) return time;
      return a.record.fixtureId.compareTo(b.record.fixtureId);
    });

    final unique = <SmartBetShadowOutcomeCase>[];
    final seenFixtures = <int>{};

    for (final item in valid) {
      if (seenFixtures.add(item.record.fixtureId)) {
        unique.add(item);
      }
    }

    if (unique.isEmpty) return null;

    double meanImprovement(List<SmartBetShadowOutcomeCase> values) {
      var total = 0.0;

      for (final item in values) {
        final outcome = item.record.status == SmartBetAnalysisStatus.correct
            ? 1.0
            : 0.0;

        final original = item.prediction.originalProbability;
        final calibrated = item.prediction.calibratedProbability;

        final originalError = original - outcome;
        final calibratedError = calibrated - outcome;

        total +=
            originalError * originalError - calibratedError * calibratedError;
      }

      return total / values.length;
    }

    final middle = unique.length ~/ 2;
    final early = unique.sublist(0, middle);
    final recent = unique.sublist(middle);

    final distinctDays = unique
        .map((item) {
          final date = item.prediction.predictedAt.toUtc();
          return '${date.year}-${date.month}-${date.day}';
        })
        .toSet()
        .length;

    var lastResolvedAt = unique.first.record.resolvedAt!.toUtc();

    for (final item in unique) {
      final resolved = item.record.resolvedAt!.toUtc();
      if (resolved.isAfter(lastResolvedAt)) {
        lastResolvedAt = resolved;
      }
    }

    return SmartBetTrialValidationEvidence(
      engine: engine,
      market: normalizedMarket,
      prospectiveFixtures: unique.length,
      distinctDays: distinctDays,
      overallBrierImprovement: meanImprovement(unique),
      earlyBrierImprovement: early.isEmpty ? 0.0 : meanImprovement(early),
      recentBrierImprovement: recent.isEmpty ? 0.0 : meanImprovement(recent),
      firstPredictionAt: unique.first.prediction.predictedAt.toUtc(),
      lastResolvedAt: lastResolvedAt,
    );
  }
}
