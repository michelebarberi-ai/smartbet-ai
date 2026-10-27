import 'smartbet_analysis_history_store.dart';
import 'smartbet_shadow_learning_store.dart';

class SmartBetShadowOutcomeCase {
  final SmartBetAnalysisRecord record;
  final SmartBetShadowPrediction prediction;

  const SmartBetShadowOutcomeCase({
    required this.record,
    required this.prediction,
  });

  bool get correct => record.status == SmartBetAnalysisStatus.correct;

  bool get adjusted =>
      (prediction.calibratedProbability - prediction.originalProbability)
          .abs() >
      1e-12;

  double get originalBrier {
    final error = prediction.originalProbability - (correct ? 1.0 : 0.0);
    return error * error;
  }

  double get calibratedBrier {
    final error = prediction.calibratedProbability - (correct ? 1.0 : 0.0);
    return error * error;
  }

  double get improvement => originalBrier - calibratedBrier;
}

class SmartBetShadowOutcomeSummary {
  final int evaluated;
  final int adjusted;
  final int improved;
  final int worsened;
  final double? originalBrier;
  final double? calibratedBrier;
  final double? adjustedOriginalBrier;
  final double? adjustedCalibratedBrier;

  const SmartBetShadowOutcomeSummary({
    required this.evaluated,
    required this.adjusted,
    required this.improved,
    required this.worsened,
    required this.originalBrier,
    required this.calibratedBrier,
    required this.adjustedOriginalBrier,
    required this.adjustedCalibratedBrier,
  });

  double? get improvement => originalBrier == null || calibratedBrier == null
      ? null
      : originalBrier! - calibratedBrier!;

  double? get adjustedImprovement =>
      adjustedOriginalBrier == null || adjustedCalibratedBrier == null
      ? null
      : adjustedOriginalBrier! - adjustedCalibratedBrier!;

  factory SmartBetShadowOutcomeSummary.fromCases(
    List<SmartBetShadowOutcomeCase> cases,
  ) {
    final changed = cases.where((c) => c.adjusted).toList();

    double? average(
      List<SmartBetShadowOutcomeCase> values,
      double Function(SmartBetShadowOutcomeCase) score,
    ) {
      if (values.isEmpty) return null;
      return values.fold<double>(0.0, (sum, item) => sum + score(item)) /
          values.length;
    }

    return SmartBetShadowOutcomeSummary(
      evaluated: cases.length,
      adjusted: changed.length,
      improved: changed.where((c) => c.improvement > 1e-12).length,
      worsened: changed.where((c) => c.improvement < -1e-12).length,
      originalBrier: average(cases, (c) => c.originalBrier),
      calibratedBrier: average(cases, (c) => c.calibratedBrier),
      adjustedOriginalBrier: average(changed, (c) => c.originalBrier),
      adjustedCalibratedBrier: average(changed, (c) => c.calibratedBrier),
    );
  }
}

class SmartBetShadowOutcomeReport {
  final List<SmartBetShadowOutcomeCase> cases;
  final SmartBetShadowOutcomeSummary overall;
  final Map<String, SmartBetShadowOutcomeSummary> byEngine;
  final Map<String, SmartBetShadowOutcomeSummary> byMarket;

  const SmartBetShadowOutcomeReport({
    required this.cases,
    required this.overall,
    required this.byEngine,
    required this.byMarket,
  });
}

/// Confronta snapshot creati prima dell'incontro con esiti reali.
/// Non modifica le probabilita' delle schedine.
class SmartBetShadowOutcomeService {
  const SmartBetShadowOutcomeService();

  SmartBetShadowOutcomeReport evaluate({
    required List<SmartBetAnalysisRecord> history,
    required List<SmartBetShadowPrediction> predictions,
  }) {
    final recordsByKey = {for (final record in history) record.key: record};

    final cases = <SmartBetShadowOutcomeCase>[];

    for (final prediction in predictions) {
      final record = recordsByKey[prediction.key];
      if (record == null) continue;

      if (!record.prospectiveEligible) continue;

      if (record.status != SmartBetAnalysisStatus.correct &&
          record.status != SmartBetAnalysisStatus.wrong) {
        continue;
      }

      final resolvedAt = record.resolvedAt;
      if (resolvedAt == null || !resolvedAt.isAfter(record.matchDate)) {
        continue;
      }

      if (!record.firstSeenAt.isBefore(record.matchDate)) {
        continue;
      }

      if (!prediction.predictedAt.isAtSameMomentAs(record.firstSeenAt)) {
        continue;
      }

      if (prediction.fixtureId != record.fixtureId ||
          prediction.engine != record.engine.name ||
          normalizeAnalysisMarket(prediction.market) !=
              normalizeAnalysisMarket(record.market)) {
        continue;
      }

      final original = prediction.originalProbability;
      final calibrated = prediction.calibratedProbability;
      final stored = record.probability;

      if (stored == null ||
          !stored.isFinite ||
          !original.isFinite ||
          !calibrated.isFinite ||
          stored < 0 ||
          stored > 1 ||
          original < 0 ||
          original > 1 ||
          calibrated < 0 ||
          calibrated > 1 ||
          (original - stored).abs() > 1e-9) {
        continue;
      }

      cases.add(
        SmartBetShadowOutcomeCase(record: record, prediction: prediction),
      );
    }

    final engineGroups = <String, List<SmartBetShadowOutcomeCase>>{};
    final marketGroups = <String, List<SmartBetShadowOutcomeCase>>{};

    for (final item in cases) {
      final engine = item.record.engine.name;
      final market = normalizeAnalysisMarket(item.record.market);

      engineGroups.putIfAbsent(engine, () => []).add(item);
      marketGroups.putIfAbsent('$engine | $market', () => []).add(item);
    }

    return SmartBetShadowOutcomeReport(
      cases: List.unmodifiable(cases),
      overall: SmartBetShadowOutcomeSummary.fromCases(cases),
      byEngine: Map.unmodifiable(
        engineGroups.map(
          (key, value) =>
              MapEntry(key, SmartBetShadowOutcomeSummary.fromCases(value)),
        ),
      ),
      byMarket: Map.unmodifiable(
        marketGroups.map(
          (key, value) =>
              MapEntry(key, SmartBetShadowOutcomeSummary.fromCases(value)),
        ),
      ),
    );
  }
}
