import 'smartbet_analysis_history_store.dart';

class SmartBetCalibrationResult {
  final double original;
  final double calibrated;
  final int sampleSize;
  final double historicalGap;
  final bool applied;

  const SmartBetCalibrationResult({
    required this.original,
    required this.calibrated,
    required this.sampleSize,
    required this.historicalGap,
    required this.applied,
  });
}

/// Calibrazione sperimentale: NON modifica le schedine live.
class SmartBetHistoricalCalibrationService {
  const SmartBetHistoricalCalibrationService();

  SmartBetCalibrationResult evaluate({
    required SmartBetAnalysisEngine engine,
    required String market,
    required double probability,
    required DateTime asOf,
    required List<SmartBetAnalysisRecord> records,
    int? fixtureId,
  }) {
    final original = probability.clamp(0.0, 1.0).toDouble();
    final cutoff = asOf.toUtc();
    final normalizedMarket = normalizeAnalysisMarket(market);

    final eligible = records.where((record) {
      if (record.engine != engine) return false;
      if (fixtureId != null && record.fixtureId == fixtureId) {
        return false;
      }
      if (normalizeAnalysisMarket(record.market) != normalizedMarket) {
        return false;
      }
      if (!record.prospectiveEligible) return false;

      if (record.status != SmartBetAnalysisStatus.correct &&
          record.status != SmartBetAnalysisStatus.wrong) {
        return false;
      }

      if (!record.matchDate.isBefore(cutoff)) return false;
      if (!record.firstSeenAt.isBefore(cutoff)) return false;

      // Conservativo: il risultato deve risultare gia'
      // registrato prima della previsione valutata.
      if (!record.lastSeenAt.isBefore(cutoff)) return false;

      final p = record.probability;
      if (p == null || !p.isFinite || p < 0 || p > 1) {
        return false;
      }

      return true;
    }).toList();

    final n = eligible.length;

    if (n < 50 || !probability.isFinite) {
      return SmartBetCalibrationResult(
        original: original,
        calibrated: original,
        sampleSize: n,
        historicalGap: 0,
        applied: false,
      );
    }

    final correct = eligible
        .where((r) => r.status == SmartBetAnalysisStatus.correct)
        .length;

    final historicalAccuracy = correct / n;

    final averagePrediction =
        eligible.fold<double>(0.0, (sum, r) => sum + r.probability!) / n;

    final gap = historicalAccuracy - averagePrediction;

    // Riduce l'impatto dei campioni piccoli.
    final shrinkage = n / (n + 100.0);

    // Massimo 10 punti percentuali di correzione.
    final adjustment = (gap * shrinkage).clamp(-0.10, 0.10).toDouble();

    final calibrated = (original + adjustment).clamp(0.01, 0.99).toDouble();

    return SmartBetCalibrationResult(
      original: original,
      calibrated: calibrated,
      sampleSize: n,
      historicalGap: gap,
      applied: true,
    );
  }
}
