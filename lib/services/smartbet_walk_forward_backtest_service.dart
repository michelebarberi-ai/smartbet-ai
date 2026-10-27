import 'smartbet_analysis_history_store.dart';
import 'smartbet_historical_calibration_service.dart';

class SmartBetWalkForwardCase {
  final int fixtureId;
  final SmartBetAnalysisEngine engine;
  final String market;
  final DateTime predictedAt;
  final double originalProbability;
  final double calibratedProbability;
  final int trainingSampleSize;
  final bool correct;
  final bool calibrationAvailable;

  const SmartBetWalkForwardCase({
    required this.fixtureId,
    required this.engine,
    required this.market,
    required this.predictedAt,
    required this.originalProbability,
    required this.calibratedProbability,
    required this.trainingSampleSize,
    required this.correct,
    required this.calibrationAvailable,
  });

  bool get adjusted =>
      (calibratedProbability - originalProbability).abs() > 1e-12;

  double get originalBrier {
    final error = originalProbability - (correct ? 1.0 : 0.0);
    return error * error;
  }

  double get calibratedBrier {
    final error = calibratedProbability - (correct ? 1.0 : 0.0);
    return error * error;
  }
}

class SmartBetWalkForwardReport {
  final List<SmartBetWalkForwardCase> cases;
  final int adjustedRecords;
  final double? originalBrier;
  final double? calibratedBrier;
  final double? originalBrierAdjusted;
  final double? calibratedBrierAdjusted;

  const SmartBetWalkForwardReport({
    required this.cases,
    required this.adjustedRecords,
    required this.originalBrier,
    required this.calibratedBrier,
    required this.originalBrierAdjusted,
    required this.calibratedBrierAdjusted,
  });

  int get evaluatedRecords => cases.length;

  double? get brierImprovement {
    if (originalBrierAdjusted == null || calibratedBrierAdjusted == null) {
      return null;
    }
    return originalBrierAdjusted! - calibratedBrierAdjusted!;
  }
}

/// Valutazione cronologica sperimentale.
/// Non cambia pronostici, ranking o schedine live.
class SmartBetWalkForwardBacktestService {
  const SmartBetWalkForwardBacktestService();

  SmartBetWalkForwardReport evaluate(List<SmartBetAnalysisRecord> records) {
    const calibration = SmartBetHistoricalCalibrationService();

    final eligible = records.where((record) {
      if (!record.prospectiveEligible) return false;

      if (record.status != SmartBetAnalysisStatus.correct &&
          record.status != SmartBetAnalysisStatus.wrong) {
        return false;
      }

      final p = record.probability;
      if (p == null || !p.isFinite || p < 0 || p > 1) {
        return false;
      }

      final resolvedAt = record.resolvedAt;

      if (resolvedAt == null) return false;
      if (!record.firstSeenAt.isBefore(record.matchDate)) {
        return false;
      }
      if (!resolvedAt.isAfter(record.matchDate)) {
        return false;
      }

      return true;
    }).toList();

    eligible.sort((a, b) {
      final time = a.firstSeenAt.compareTo(b.firstSeenAt);
      if (time != 0) return time;

      final fixture = a.fixtureId.compareTo(b.fixtureId);
      if (fixture != 0) return fixture;

      final engine = a.engine.index.compareTo(b.engine.index);
      if (engine != 0) return engine;

      return a.market.compareTo(b.market);
    });

    final cases = <SmartBetWalkForwardCase>[];

    for (final record in eligible) {
      final result = calibration.evaluate(
        engine: record.engine,
        market: record.market,
        probability: record.probability!,
        asOf: record.firstSeenAt,
        records: records,
        fixtureId: record.fixtureId,
      );

      cases.add(
        SmartBetWalkForwardCase(
          fixtureId: record.fixtureId,
          engine: record.engine,
          market: record.market,
          predictedAt: record.firstSeenAt,
          originalProbability: result.original,
          calibratedProbability: result.calibrated,
          trainingSampleSize: result.sampleSize,
          correct: record.status == SmartBetAnalysisStatus.correct,
          calibrationAvailable: result.applied,
        ),
      );
    }

    final adjusted = cases.where((item) => item.adjusted).toList();

    return SmartBetWalkForwardReport(
      cases: List.unmodifiable(cases),
      adjustedRecords: adjusted.length,
      originalBrier: _mean(cases, (item) => item.originalBrier),
      calibratedBrier: _mean(cases, (item) => item.calibratedBrier),
      originalBrierAdjusted: _mean(adjusted, (item) => item.originalBrier),
      calibratedBrierAdjusted: _mean(adjusted, (item) => item.calibratedBrier),
    );
  }

  static double? _mean(
    List<SmartBetWalkForwardCase> cases,
    double Function(SmartBetWalkForwardCase) value,
  ) {
    if (cases.isEmpty) return null;

    final sum = cases.fold<double>(0.0, (total, item) => total + value(item));

    return sum / cases.length;
  }
}
