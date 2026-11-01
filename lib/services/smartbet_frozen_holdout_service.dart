import 'smartbet_analysis_history_store.dart';
import 'smartbet_historical_calibration_service.dart';
import 'smartbet_shadow_outcome_service.dart';

class SmartBetFrozenHoldoutReport {
  final int trainingFixtures;
  final int validationFixtures;
  final int distinctValidationDays;
  final double? originalBrier;
  final double? frozenCalibratedBrier;

  const SmartBetFrozenHoldoutReport({
    required this.trainingFixtures,
    required this.validationFixtures,
    required this.distinctValidationDays,
    required this.originalBrier,
    required this.frozenCalibratedBrier,
  });

  double? get brierImprovement =>
      originalBrier == null || frozenCalibratedBrier == null
      ? null
      : originalBrier! - frozenCalibratedBrier!;

  bool get sufficientForExploratoryReview =>
      trainingFixtures >= 50 &&
      validationFixtures >= 30 &&
      distinctValidationDays >= 10;
}

/// Backtest retrospettivo con addestramento congelato.
/// Nessuna modifica agli snapshot o alle previsioni live.
///
/// Non costituisce ancora approvazione di un modello
/// preregistrato per uso operativo.
class SmartBetFrozenHoldoutService {
  const SmartBetFrozenHoldoutService();

  SmartBetFrozenHoldoutReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required Iterable<SmartBetShadowOutcomeCase> cases,
    required SmartBetAnalysisEngine engine,
    required String market,
    required DateTime trainingCutoff,
    required DateTime validationStartsAt,
    required DateTime asOf,
  }) {
    final freeze = trainingCutoff.toUtc();
    final start = validationStartsAt.toUtc();
    final end = asOf.toUtc();
    final normalized = normalizeAnalysisMarket(market);

    if (!freeze.isBefore(start) || !start.isBefore(end) || normalized.isEmpty) {
      throw ArgumentError(
        'Intervalli temporali di addestramento e validazione non validi',
      );
    }

    bool eligibleRecord(SmartBetAnalysisRecord record, DateTime resultCutoff) {
      final probability = record.probability;
      final resolved = record.resolvedAt?.toUtc();
      final kickoff = record.matchDate.toUtc();

      return record.engine == engine &&
          normalizeAnalysisMarket(record.market) == normalized &&
          record.fixtureId > 0 &&
          record.prospectiveEligible &&
          record.hasActualResult &&
          record.asianSettlement == null &&
          (engine != SmartBetAnalysisEngine.diego ||
              record.qualified == true) &&
          probability != null &&
          probability.isFinite &&
          probability >= 0 &&
          probability <= 1 &&
          (record.status == SmartBetAnalysisStatus.correct ||
              record.status == SmartBetAnalysisStatus.wrong) &&
          record.firstSeenAt.toUtc().isBefore(kickoff) &&
          resolved != null &&
          resolved.isAfter(kickoff) &&
          resolved.isBefore(resultCutoff);
    }

    final trainingCandidates =
        records
            .where(
              (record) =>
                  eligibleRecord(record, freeze) &&
                  record.matchDate.toUtc().isBefore(freeze),
            )
            .toList()
          ..sort((a, b) {
            final date = a.firstSeenAt.compareTo(b.firstSeenAt);
            return date != 0 ? date : a.fixtureId.compareTo(b.fixtureId);
          });

    // Una partita contribuisce una sola volta
    // al medesimo mercato del medesimo motore.
    final trainingByFixture = <int, SmartBetAnalysisRecord>{};

    for (final record in trainingCandidates) {
      trainingByFixture.putIfAbsent(record.fixtureId, () => record);
    }

    final training = trainingByFixture.values.toList();
    final validation = cases.toList()
      ..sort((a, b) {
        final date = a.prediction.predictedAt.compareTo(
          b.prediction.predictedAt,
        );
        return date != 0
            ? date
            : a.record.fixtureId.compareTo(b.record.fixtureId);
      });

    final seenValidation = <int>{};
    final days = <String>{};

    var count = 0;
    var originalSum = 0.0;
    var frozenSum = 0.0;

    const calibrator = SmartBetHistoricalCalibrationService();

    for (final item in validation) {
      final record = item.record;
      final snapshot = item.prediction;
      final predicted = snapshot.predictedAt.toUtc();
      final original = snapshot.originalProbability;
      final stored = record.probability;

      if (!eligibleRecord(record, end) ||
          !predicted.isAfter(start) ||
          !predicted.isBefore(record.matchDate.toUtc()) ||
          !predicted.isAtSameMomentAs(record.firstSeenAt.toUtc()) ||
          snapshot.key != record.key ||
          snapshot.engine != engine.name ||
          normalizeAnalysisMarket(snapshot.market) != normalized ||
          snapshot.fixtureId != record.fixtureId ||
          stored == null ||
          !original.isFinite ||
          (stored - original).abs() > 1e-9 ||
          seenValidation.contains(record.fixtureId)) {
        continue;
      }

      // Calibrazione ricostruita utilizzando esclusivamente
      // risultati già disponibili prima del congelamento.
      final calibration = calibrator.evaluate(
        engine: engine,
        market: normalized,
        probability: original,
        asOf: freeze,
        records: training,
        fixtureId: record.fixtureId,
      );

      if (!calibration.applied || !calibration.calibrated.isFinite) {
        continue;
      }

      final outcome = record.status == SmartBetAnalysisStatus.correct
          ? 1.0
          : 0.0;

      final originalError = original - outcome;
      final calibratedError = calibration.calibrated - outcome;

      originalSum += originalError * originalError;
      frozenSum += calibratedError * calibratedError;

      seenValidation.add(record.fixtureId);
      days.add('${predicted.year}-${predicted.month}-${predicted.day}');
      count++;
    }

    return SmartBetFrozenHoldoutReport(
      trainingFixtures: training.length,
      validationFixtures: count,
      distinctValidationDays: days.length,
      originalBrier: count == 0 ? null : originalSum / count,
      frozenCalibratedBrier: count == 0 ? null : frozenSum / count,
    );
  }
}
