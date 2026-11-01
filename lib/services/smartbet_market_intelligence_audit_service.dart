import 'smartbet_analysis_history_store.dart';

/// Analisi diagnostica: non modifica pronostici né schedine.
class MarketIntelligenceMetrics {
  final SmartBetAnalysisEngine engine;
  final String market;
  final int samples;
  final int correct;
  final double meanProbability;
  final double observedFrequency;
  final double brierScore;
  final int quotedSamples;
  final double? meanQuotedProbability;
  final double? meanImpliedProbability;
  final double? marketGap;
  final double? hypotheticalUnitRoi;

  const MarketIntelligenceMetrics({
    required this.engine,
    required this.market,
    required this.samples,
    required this.correct,
    required this.meanProbability,
    required this.observedFrequency,
    required this.brierScore,
    required this.quotedSamples,
    required this.meanQuotedProbability,
    required this.meanImpliedProbability,
    required this.marketGap,
    required this.hypotheticalUnitRoi,
  });
}

class MarketIntelligenceReport {
  final List<MarketIntelligenceMetrics> groups;
  final int includedRecords;
  final int excludedRecords;

  const MarketIntelligenceReport({
    required this.groups,
    required this.includedRecords,
    required this.excludedRecords,
  });
}

class MarketIntelligenceAuditService {
  const MarketIntelligenceAuditService();

  MarketIntelligenceReport evaluate(Iterable<SmartBetAnalysisRecord> records) {
    final buckets = <String, _MarketBucket>{};
    final seen = <String>{};
    var included = 0;
    var excluded = 0;

    for (final record in records) {
      if (!_eligible(record) || !seen.add(record.key)) {
        excluded++;
        continue;
      }

      included++;

      final market = normalizeAnalysisMarket(record.market);
      final key = '${record.engine.name}|$market';

      final bucket = buckets.putIfAbsent(
        key,
        () => _MarketBucket(record.engine, market),
      );

      final probability = record.probability!;
      final won = record.status == SmartBetAnalysisStatus.correct;
      final outcome = won ? 1.0 : 0.0;

      bucket.samples++;
      if (won) bucket.correct++;

      bucket.probabilitySum += probability;
      final error = probability - outcome;
      bucket.brierSum += error * error;

      final odd = record.quotedOdd;

      // Le quote sono un filtro di disponibilità e una
      // misura diagnostica, non una sorgente di probabilità AI.
      if (odd != null && odd.isFinite && odd >= 1.25) {
        bucket.quotedSamples++;
        bucket.quotedProbabilitySum += probability;
        bucket.impliedProbabilitySum += 1.0 / odd;

        // Simulazione teorica: una unità su ogni selezione.
        bucket.theoreticalProfit += won ? odd - 1.0 : -1.0;
      }
    }

    final groups =
        buckets.values.map((bucket) {
          final n = bucket.samples;
          final q = bucket.quotedSamples;

          final meanQuoted = q > 0 ? bucket.quotedProbabilitySum / q : null;

          final meanImplied = q > 0 ? bucket.impliedProbabilitySum / q : null;

          return MarketIntelligenceMetrics(
            engine: bucket.engine,
            market: bucket.market,
            samples: n,
            correct: bucket.correct,
            meanProbability: bucket.probabilitySum / n,
            observedFrequency: bucket.correct / n,
            brierScore: bucket.brierSum / n,
            quotedSamples: q,
            meanQuotedProbability: meanQuoted,
            meanImpliedProbability: meanImplied,
            marketGap: meanQuoted != null && meanImplied != null
                ? meanQuoted - meanImplied
                : null,
            hypotheticalUnitRoi: q > 0 ? bucket.theoreticalProfit / q : null,
          );
        }).toList()..sort((a, b) {
          final engineOrder = a.engine.index.compareTo(b.engine.index);
          return engineOrder != 0 ? engineOrder : a.market.compareTo(b.market);
        });

    return MarketIntelligenceReport(
      groups: List.unmodifiable(groups),
      includedRecords: included,
      excludedRecords: excluded,
    );
  }

  bool _eligible(SmartBetAnalysisRecord record) {
    // Le letture Diego non qualificate restano informative.
    if (record.engine == SmartBetAnalysisEngine.diego &&
        record.qualified != true) {
      return false;
    }

    final probability = record.probability;
    final resolvedAt = record.resolvedAt;

    if (!record.prospectiveEligible ||
        probability == null ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1 ||
        resolvedAt == null ||
        !record.hasActualResult ||
        record.asianSettlement != null) {
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

class _MarketBucket {
  final SmartBetAnalysisEngine engine;
  final String market;

  int samples = 0;
  int correct = 0;
  int quotedSamples = 0;

  double probabilitySum = 0;
  double brierSum = 0;
  double quotedProbabilitySum = 0;
  double impliedProbabilitySum = 0;
  double theoreticalProfit = 0;

  _MarketBucket(this.engine, this.market);
}
