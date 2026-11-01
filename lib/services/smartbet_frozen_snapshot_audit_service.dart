import 'smartbet_analysis_history_store.dart';
import 'smartbet_frozen_model_snapshot_store.dart';
import 'smartbet_shadow_outcome_service.dart';

class SmartBetFrozenSnapshotAuditReport {
  final String modelId;
  final int validationFixtures;
  final int distinctDays;
  final int excludedCases;
  final double? originalBrier;
  final double? frozenBrier;
  final double? earlyImprovement;
  final double? recentImprovement;

  const SmartBetFrozenSnapshotAuditReport({
    required this.modelId,
    required this.validationFixtures,
    required this.distinctDays,
    required this.excludedCases,
    required this.originalBrier,
    required this.frozenBrier,
    required this.earlyImprovement,
    required this.recentImprovement,
  });

  double? get brierImprovement => originalBrier == null || frozenBrier == null
      ? null
      : originalBrier! - frozenBrier!;

  /// Solo soglia esplorativa: NON autorizza il live.
  bool get enoughForExploratoryReview =>
      validationFixtures >= 30 && distinctDays >= 10;
}

/// Audit retrospettivo di uno snapshot congelato.
/// Ricalcola la probabilità usando il modello fornito.
/// Non utilizza la vecchia calibratedProbability come
/// prova della correzione del modello congelato.
class SmartBetFrozenSnapshotAuditService {
  const SmartBetFrozenSnapshotAuditService();

  SmartBetFrozenSnapshotAuditReport evaluate({
    required SmartBetFrozenModelSnapshot model,
    required Iterable<SmartBetShadowOutcomeCase> cases,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();

    if (!model.frozenAt.toUtc().isBefore(cutoff)) {
      throw ArgumentError('Il congelamento deve precedere il cutoff');
    }

    final eligible = <SmartBetShadowOutcomeCase>[];
    var excluded = 0;

    for (final item in cases) {
      final record = item.record;
      final prediction = item.prediction;
      final kickoff = record.matchDate.toUtc();
      final predicted = prediction.predictedAt.toUtc();
      final resolved = record.resolvedAt?.toUtc();
      final stored = record.probability;
      final original = prediction.originalProbability;

      final valid =
          record.engine == model.engine &&
          prediction.engine == model.engine.name &&
          normalizeAnalysisMarket(record.market) == model.market &&
          normalizeAnalysisMarket(prediction.market) == model.market &&
          record.fixtureId > 0 &&
          prediction.fixtureId == record.fixtureId &&
          prediction.key == record.key &&
          record.prospectiveEligible &&
          record.hasActualResult &&
          record.asianSettlement == null &&
          (model.engine != SmartBetAnalysisEngine.diego ||
              record.qualified == true) &&
          (record.status == SmartBetAnalysisStatus.correct ||
              record.status == SmartBetAnalysisStatus.wrong) &&
          stored != null &&
          stored.isFinite &&
          stored >= 0 &&
          stored <= 1 &&
          original.isFinite &&
          original >= 0 &&
          original <= 1 &&
          (stored - original).abs() <= 1e-9 &&
          record.firstSeenAt.toUtc().isAtSameMomentAs(predicted) &&
          predicted.isAfter(model.frozenAt.toUtc()) &&
          predicted.isBefore(kickoff) &&
          resolved != null &&
          resolved.isAfter(kickoff) &&
          resolved.isBefore(cutoff);

      if (!valid) {
        excluded++;
        continue;
      }

      eligible.add(item);
    }

    eligible.sort((a, b) {
      final time = a.prediction.predictedAt.compareTo(b.prediction.predictedAt);
      if (time != 0) return time;
      return a.record.fixtureId.compareTo(b.record.fixtureId);
    });

    final unique = <SmartBetShadowOutcomeCase>[];
    final seenFixtures = <int>{};

    for (final item in eligible) {
      if (seenFixtures.add(item.record.fixtureId)) {
        unique.add(item);
      } else {
        excluded++;
      }
    }

    double originalScore(SmartBetShadowOutcomeCase item) {
      final outcome = item.record.status == SmartBetAnalysisStatus.correct
          ? 1.0
          : 0.0;

      final error = item.prediction.originalProbability - outcome;
      return error * error;
    }

    double frozenScore(SmartBetShadowOutcomeCase item) {
      final outcome = item.record.status == SmartBetAnalysisStatus.correct
          ? 1.0
          : 0.0;

      final calibrated = model.calibratedProbability(
        item.prediction.originalProbability,
      );

      final error = calibrated - outcome;
      return error * error;
    }

    double? mean(
      List<SmartBetShadowOutcomeCase> values,
      double Function(SmartBetShadowOutcomeCase) score,
    ) {
      if (values.isEmpty) return null;

      final sum = values.fold<double>(
        0.0,
        (total, item) => total + score(item),
      );

      return sum / values.length;
    }

    double? improvement(List<SmartBetShadowOutcomeCase> values) {
      final original = mean(values, originalScore);
      final frozen = mean(values, frozenScore);

      if (original == null || frozen == null) return null;
      return original - frozen;
    }

    final middle = unique.length ~/ 2;
    final early = unique.sublist(0, middle);
    final recent = unique.sublist(middle);

    final days = unique.map((item) {
      final date = item.prediction.predictedAt.toUtc();
      return '${date.year}-${date.month}-${date.day}';
    }).toSet();

    return SmartBetFrozenSnapshotAuditReport(
      modelId: model.id,
      validationFixtures: unique.length,
      distinctDays: days.length,
      excludedCases: excluded,
      originalBrier: mean(unique, originalScore),
      frozenBrier: mean(unique, frozenScore),
      earlyImprovement: improvement(early),
      recentImprovement: improvement(recent),
    );
  }
}
