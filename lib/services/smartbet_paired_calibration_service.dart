import 'smartbet_analysis_history_store.dart';

class SmartBetPairedCalibrationMetrics {
  final String market;
  final int pairedFixtures;
  final int distinctDays;
  final double smartBetBrier;
  final double diegoBrier;

  const SmartBetPairedCalibrationMetrics({
    required this.market,
    required this.pairedFixtures,
    required this.distinctDays,
    required this.smartBetBrier,
    required this.diegoBrier,
  });

  /// Positivo: Brier SmartBet inferiore.
  /// Negativo: Brier Diego inferiore.
  double get smartBetBrierAdvantage => diegoBrier - smartBetBrier;

  /// Soglia operativa esplorativa, non prova
  /// di significatività statistica.
  bool get enoughForExploratoryReview =>
      pairedFixtures >= 30 && distinctDays >= 10;
}

class SmartBetPairedCalibrationReport {
  final List<SmartBetPairedCalibrationMetrics> markets;
  final int totalPairs;

  const SmartBetPairedCalibrationReport({
    required this.markets,
    required this.totalPairs,
  });
}

/// Confronta le probabilità dei due motori soltanto
/// sulla stessa fixture e sullo stesso mercato.
/// Nessuna lettura/scrittura su rete o archivio.
class SmartBetPairedCalibrationService {
  const SmartBetPairedCalibrationService();

  SmartBetPairedCalibrationReport evaluate(
    Iterable<SmartBetAnalysisRecord> records,
  ) {
    final candidates =
        <String, Map<SmartBetAnalysisEngine, SmartBetAnalysisRecord>>{};

    for (final record in records) {
      if (!_eligible(record)) continue;

      final market = normalizeAnalysisMarket(record.market);
      final key = '${record.fixtureId}|$market';

      final engines = candidates.putIfAbsent(
        key,
        () => <SmartBetAnalysisEngine, SmartBetAnalysisRecord>{},
      );

      // Lo storico è deduplicato per motore/fixture/mercato.
      // Non conteggiare due volte lo stesso pronostico.
      engines.putIfAbsent(record.engine, () => record);
    }

    final buckets = <String, _PairedBucket>{};
    var totalPairs = 0;

    for (final engines in candidates.values) {
      final smartBet = engines[SmartBetAnalysisEngine.smartBet];
      final diego = engines[SmartBetAnalysisEngine.diego];

      if (smartBet == null || diego == null) continue;

      // La stessa fixture e lo stesso mercato devono
      // avere identici risultato ed esito.
      if (smartBet.status != diego.status ||
          smartBet.actualHomeGoals != diego.actualHomeGoals ||
          smartBet.actualAwayGoals != diego.actualAwayGoals ||
          !smartBet.matchDate.toUtc().isAtSameMomentAs(
            diego.matchDate.toUtc(),
          )) {
        continue;
      }

      final market = normalizeAnalysisMarket(smartBet.market);
      final bucket = buckets.putIfAbsent(market, () => _PairedBucket());

      final observed = smartBet.status == SmartBetAnalysisStatus.correct
          ? 1.0
          : 0.0;

      final sbError = smartBet.probability! - observed;
      final diegoError = diego.probability! - observed;

      bucket.pairs++;
      bucket.smartBetBrierSum += sbError * sbError;
      bucket.diegoBrierSum += diegoError * diegoError;

      final date = smartBet.matchDate.toUtc();
      bucket.days.add('${date.year}-${date.month}-${date.day}');

      totalPairs++;
    }

    final markets =
        buckets.entries.map((entry) {
          final bucket = entry.value;

          return SmartBetPairedCalibrationMetrics(
            market: entry.key,
            pairedFixtures: bucket.pairs,
            distinctDays: bucket.days.length,
            smartBetBrier: bucket.smartBetBrierSum / bucket.pairs,
            diegoBrier: bucket.diegoBrierSum / bucket.pairs,
          );
        }).toList()..sort((a, b) {
          final count = b.pairedFixtures.compareTo(a.pairedFixtures);
          return count != 0 ? count : a.market.compareTo(b.market);
        });

    return SmartBetPairedCalibrationReport(
      markets: List.unmodifiable(markets),
      totalPairs: totalPairs,
    );
  }

  bool _eligible(SmartBetAnalysisRecord record) {
    final p = record.probability;
    final resolvedAt = record.resolvedAt;

    if (!record.prospectiveEligible ||
        p == null ||
        !p.isFinite ||
        p < 0 ||
        p > 1 ||
        resolvedAt == null ||
        !record.hasActualResult ||
        record.asianSettlement != null) {
      return false;
    }

    if (record.engine == SmartBetAnalysisEngine.diego &&
        record.qualified != true) {
      return false;
    }

    if (record.status != SmartBetAnalysisStatus.correct &&
        record.status != SmartBetAnalysisStatus.wrong) {
      return false;
    }

    if (!record.firstSeenAt.toUtc().isBefore(record.matchDate.toUtc()) ||
        !resolvedAt.toUtc().isAfter(record.matchDate.toUtc())) {
      return false;
    }

    return normalizeAnalysisMarket(record.market).isNotEmpty;
  }
}

class _PairedBucket {
  int pairs = 0;
  double smartBetBrierSum = 0;
  double diegoBrierSum = 0;
  final Set<String> days = {};
}
