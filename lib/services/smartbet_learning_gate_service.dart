import 'smartbet_analysis_history_store.dart';
import 'smartbet_shadow_outcome_service.dart';

enum SmartBetLearningGateStatus {
  insufficientData,
  inconsistentImprovement,
  eligibleForTrial,
}

class SmartBetLearningGateDecision {
  final String engine;
  final String market;
  final int adjustedSamples;
  final int distinctDays;
  final double? overallImprovement;
  final double? earlyImprovement;
  final double? recentImprovement;
  final SmartBetLearningGateStatus status;

  const SmartBetLearningGateDecision({
    required this.engine,
    required this.market,
    required this.adjustedSamples,
    required this.distinctDays,
    required this.overallImprovement,
    required this.earlyImprovement,
    required this.recentImprovement,
    required this.status,
  });

  bool get eligibleForTrial =>
      status == SmartBetLearningGateStatus.eligibleForTrial;
}

class SmartBetLearningGateReport {
  final List<SmartBetLearningGateDecision> decisions;

  const SmartBetLearningGateReport({required this.decisions});

  int get eligibleMarkets =>
      decisions.where((decision) => decision.eligibleForTrial).length;
}

/// Controllo sperimentale della calibrazione.
///
/// Non abilita autonomamente correzioni nelle schedine.
/// Valuta soltanto evidenze raccolte in modalita' shadow.
class SmartBetLearningGateService {
  const SmartBetLearningGateService();

  static const int minimumAdjustedSamples = 100;
  static const int minimumDistinctDays = 14;

  static const double minimumOverallImprovement = 0.002;
  static const double minimumHalfImprovement = 0.001;

  SmartBetLearningGateReport evaluate(
    SmartBetShadowOutcomeReport report, {
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final groups = <String, List<SmartBetShadowOutcomeCase>>{};

    for (final item in report.cases) {
      final record = item.record;
      final prediction = item.prediction;
      final resolvedAt = record.resolvedAt;

      if (record.key != prediction.key ||
          !record.prospectiveEligible ||
          (record.status != SmartBetAnalysisStatus.correct &&
              record.status != SmartBetAnalysisStatus.wrong) ||
          resolvedAt == null ||
          !resolvedAt.isAfter(record.matchDate) ||
          !resolvedAt.isBefore(cutoff) ||
          !record.firstSeenAt.isBefore(record.matchDate) ||
          !record.firstSeenAt.isAtSameMomentAs(prediction.predictedAt)) {
        continue;
      }

      if (!item.adjusted || !item.prediction.calibrationApplied) {
        continue;
      }

      final engine = item.record.engine.name;
      final market = normalizeAnalysisMarket(item.record.market);
      final key = '$engine|$market';

      groups.putIfAbsent(key, () => []).add(item);
    }

    final decisions = <SmartBetLearningGateDecision>[];

    for (final entry in groups.entries) {
      final values = entry.value.toList()
        ..sort((a, b) {
          final date = a.prediction.predictedAt.compareTo(
            b.prediction.predictedAt,
          );

          if (date != 0) return date;

          return a.record.fixtureId.compareTo(b.record.fixtureId);
        });

      final engine = values.first.record.engine.name;
      final market = normalizeAnalysisMarket(values.first.record.market);

      final uniqueFixtures = values
          .map((item) => item.record.fixtureId)
          .toSet()
          .length;

      final days = values
          .map((item) {
            final date = item.prediction.predictedAt.toUtc();
            return '${date.year}-${date.month}-${date.day}';
          })
          .toSet()
          .length;

      final middle = values.length ~/ 2;

      final overall = _meanImprovement(values);
      final early = middle == 0
          ? null
          : _meanImprovement(values.sublist(0, middle));
      final recent = middle == values.length
          ? null
          : _meanImprovement(values.sublist(middle));

      final enoughData =
          values.length >= minimumAdjustedSamples &&
          uniqueFixtures >= minimumAdjustedSamples &&
          days >= minimumDistinctDays;

      final status = !enoughData
          ? SmartBetLearningGateStatus.insufficientData
          : overall != null &&
                early != null &&
                recent != null &&
                overall >= minimumOverallImprovement &&
                early >= minimumHalfImprovement &&
                recent >= minimumHalfImprovement
          ? SmartBetLearningGateStatus.eligibleForTrial
          : SmartBetLearningGateStatus.inconsistentImprovement;

      decisions.add(
        SmartBetLearningGateDecision(
          engine: engine,
          market: market,
          adjustedSamples: values.length,
          distinctDays: days,
          overallImprovement: overall,
          earlyImprovement: early,
          recentImprovement: recent,
          status: status,
        ),
      );
    }

    decisions.sort((a, b) {
      final engine = a.engine.compareTo(b.engine);
      if (engine != 0) return engine;
      return a.market.compareTo(b.market);
    });

    return SmartBetLearningGateReport(decisions: List.unmodifiable(decisions));
  }

  static double? _meanImprovement(List<SmartBetShadowOutcomeCase> values) {
    if (values.isEmpty) return null;

    final sum = values.fold<double>(
      0.0,
      (total, item) => total + item.improvement,
    );

    return sum / values.length;
  }
}
