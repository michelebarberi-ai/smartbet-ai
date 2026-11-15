import 'dart:math' as math;

import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';

/// B56 QuoteLab: third, read-only statistical observation layer.
///
/// Unlike SmartBet or Diego, this never predicts sport outcomes and never
/// selects a coupon. It describes actual hit rates for historic QUOTED picks.
/// A quote is a market observation, not a true probability.
class QuoteLabPriceBand {
  final String label;
  final double lowerInclusive;
  final double upperExclusive;

  const QuoteLabPriceBand(this.label, this.lowerInclusive, this.upperExclusive);

  static const bands = <QuoteLabPriceBand>[
    QuoteLabPriceBand('1.01–1.19', 1.0, 1.20),
    QuoteLabPriceBand('1.20–1.29', 1.20, 1.30),
    QuoteLabPriceBand('1.30–1.49', 1.30, 1.50),
    QuoteLabPriceBand('1.50–1.69', 1.50, 1.70),
    QuoteLabPriceBand('1.70–1.89', 1.70, 1.90),
    QuoteLabPriceBand('1.90–2.19', 1.90, 2.20),
    QuoteLabPriceBand('2.20–2.99', 2.20, 3.0),
    QuoteLabPriceBand('3.00–4.99', 3.0, 5.0),
    QuoteLabPriceBand('5.00+', 5.0, double.infinity),
  ];

  static QuoteLabPriceBand? fromOdd(double price) {
    if (!price.isFinite || price <= 1 || price > 1000) return null;
    for (final band in bands) {
      if (price >= band.lowerInclusive && price < band.upperExclusive) {
        return band;
      }
    }
    return null;
  }
}

enum QuoteLabEvidenceLevel { insufficient, exploratory, needsValidation }

class QuoteLabPriceSegment {
  final String country;
  final String league;
  final String market;
  final QuoteLabPriceBand priceBand;
  final int observations;
  final int successes;
  final int matchDays;
  final double hitRatePercent;
  final double wilsonLower95Percent;
  final double wilsonUpper95Percent;
  final double averagePrice;
  /// Gross 1 / decimal odds, NOT de-vigged implied probability.
  final double averageGrossImpliedPercent;
  final double? averageSmartBetOrDiegoPercent;
  /// Net hypothetical return per 1 staked on EVERY observed quoted pick.
  /// Selection-biased: not a live strategy or a profit forecast.
  final double historicalRoiPercent;
  final QuoteLabEvidenceLevel evidenceLevel;

  const QuoteLabPriceSegment({
    required this.country,
    required this.league,
    required this.market,
    required this.priceBand,
    required this.observations,
    required this.successes,
    required this.matchDays,
    required this.hitRatePercent,
    required this.wilsonLower95Percent,
    required this.wilsonUpper95Percent,
    required this.averagePrice,
    required this.averageGrossImpliedPercent,
    required this.averageSmartBetOrDiegoPercent,
    required this.historicalRoiPercent,
    required this.evidenceLevel,
  });

  bool get isAllLeagues => country == 'TUTTI' && league == 'TUTTI';
  double get gapFromGrossImpliedPoints =>
      hitRatePercent - averageGrossImpliedPercent;
}

class QuoteLabHistoricalReport {
  final int sourceRecords;
  final int usableQuotedOutcomes;
  final int excludedRecords;
  final int duplicates;
  final int conflicts;
  final List<QuoteLabPriceSegment> segments;
  const QuoteLabHistoricalReport({
    required this.sourceRecords,
    required this.usableQuotedOutcomes,
    required this.excludedRecords,
    required this.duplicates,
    required this.conflicts,
    required this.segments,
  });

  /// QuoteLab is strictly informative, NOT an input to sports probabilities.
  bool get changesSmartBetOrDiego => false;
  bool get selectsCoupon => false;
}

/// Uses the pre-kickoff quote first saved for a prediction and the actual
/// resolved outcome. Local records are only SELECTED picks, not all
/// bookmaker prices: results must never be generalized to the market.
class QuoteLabHistoricalService {
  const QuoteLabHistoricalService();

  static const int minimumExploratory = 30;
  static const int minimumIndicative = 100;
  static const int minimumDistinctDays = 14;

  QuoteLabHistoricalReport evaluate({
    required Iterable<SmartBetAnalysisRecord> history,
    required DateTime asOf,
  }) {
    final source = history.toList(growable: false);
    final cutoff = asOf.toUtc();
    final unique = <String, SmartBetAnalysisRecord>{};
    final conflicts = <String>{};
    var excluded = 0;
    var duplicates = 0;

    for (final record in source) {
      final quote = record.quotedOdd;
      final kickoff = record.matchDate.toUtc();
      final firstSeen = record.firstSeenAt.toUtc();
      final knownAt = record.outcomeKnownBy?.toUtc();
      final market = normalizeAnalysisMarket(record.market);
      final band = quote == null ? null : QuoteLabPriceBand.fromOdd(quote);
      final settled = record.status == SmartBetAnalysisStatus.correct ||
          record.status == SmartBetAnalysisStatus.wrong;
      if (!record.prospectiveEligible ||
          record.fixtureId <= 0 ||
          record.country.trim().isEmpty ||
          record.league.trim().isEmpty ||
          market.isEmpty ||
          band == null ||
          !firstSeen.isBefore(kickoff) ||
          !settled ||
          knownAt == null ||
          !knownAt.isAfter(kickoff) ||
          knownAt.isAfter(cutoff) ||
          record.actualHomeGoals == null ||
          record.actualAwayGoals == null ||
          record.actualHomeGoals! < 0 ||
          record.actualAwayGoals! < 0 ||
          (record.probability != null &&
              (!record.probability!.isFinite ||
                  record.probability! < 0 ||
                  record.probability! > 1))) {
        excluded++;
        continue;
      }
      // Re-derive the outcome from the final score: never trust a stale
      // correct/wrong flag, and exclude non-settleable market definitions.
      final verified = SmartBetAnalysisMarketSettlement.evaluate(
        market: market,
        homeGoals: record.actualHomeGoals!,
        awayGoals: record.actualAwayGoals!,
      );
      if (verified == SmartBetAnalysisSettlement.unsupported ||
          (record.status == SmartBetAnalysisStatus.correct &&
              verified != SmartBetAnalysisSettlement.correct) ||
          (record.status == SmartBetAnalysisStatus.wrong &&
              verified != SmartBetAnalysisSettlement.wrong)) {
        excluded++;
        continue;
      }
      // Never count the same fixture/market twice for the same engine.
      final key = '${record.engine.name}|${record.fixtureId}|$market';
      if (conflicts.contains(key)) continue;
      final previous = unique[key];
      if (previous == null) {
        unique[key] = record;
      } else if (previous.status != record.status ||
          previous.quotedOdd != quote ||
          previous.matchDate.toUtc() != kickoff ||
          previous.country.trim() != record.country.trim() ||
          previous.league.trim() != record.league.trim() ||
          previous.actualHomeGoals != record.actualHomeGoals ||
          previous.actualAwayGoals != record.actualAwayGoals) {
        conflicts.add(key);
        unique.remove(key);
      } else {
        duplicates++;
      }
    }

    final buckets = <String, _QuoteLabBucket>{};
    for (final record in unique.values) {
      final market = normalizeAnalysisMarket(record.market);
      final band = QuoteLabPriceBand.fromOdd(record.quotedOdd!)!;
      final country = record.country.trim();
      final league = record.league.trim();
      // Global and league-specific buckets use disjoint keys; each record
      // has one vote in each *view*, never two votes within a view.
      for (final dimensions in <(String, String)>[
        ('TUTTI', 'TUTTI'),
        (country, league),
      ]) {
        final key = '${dimensions.$1}|${dimensions.$2}|$market|${band.label}';
        buckets.putIfAbsent(
          key,
          () => _QuoteLabBucket(dimensions.$1, dimensions.$2, market, band),
        ).add(record);
      }
    }

    final segments = buckets.values.map((b) => b.finish()).toList()
      ..sort((a, b) {
        final scope = (b.isAllLeagues ? 1 : 0).compareTo(
          a.isAllLeagues ? 1 : 0,
        );
        if (scope != 0) return scope;
        final n = b.observations.compareTo(a.observations);
        if (n != 0) return n;
        return '${a.country}|${a.league}|${a.market}|${a.priceBand.label}'
            .compareTo('${b.country}|${b.league}|${b.market}|${b.priceBand.label}');
      });
    return QuoteLabHistoricalReport(
      sourceRecords: source.length,
      usableQuotedOutcomes: unique.length,
      excludedRecords: excluded,
      duplicates: duplicates,
      conflicts: conflicts.length,
      segments: List.unmodifiable(segments),
    );
  }
}

class _QuoteLabBucket {
  final String country;
  final String league;
  final String market;
  final QuoteLabPriceBand band;
  final Set<String> days = {};
  var n = 0;
  var wins = 0;
  var sumPrices = 0.0;
  var sumGrossImplied = 0.0;
  var netUnits = 0.0;
  var sumPrediction = 0.0;
  var predictionN = 0;

  _QuoteLabBucket(this.country, this.league, this.market, this.band);

  void add(SmartBetAnalysisRecord r) {
    final odd = r.quotedOdd!;
    final win = r.status == SmartBetAnalysisStatus.correct;
    n++;
    if (win) wins++;
    sumPrices += odd;
    sumGrossImplied += 1 / odd;
    netUnits += win ? odd - 1 : -1;
    final p = r.probability;
    if (p != null) {
      predictionN++;
      sumPrediction += p;
    }
    days.add(r.matchDate.toUtc().toIso8601String().substring(0, 10));
  }

  QuoteLabPriceSegment finish() {
    final p = wins / n;
    const z = 1.959963984540054;
    final zz = z * z;
    final divisor = 1 + zz / n;
    final center = (p + zz / (2 * n)) / divisor;
    final margin = z * math.sqrt(
      p * (1 - p) / n + zz / (4 * n * n),
    ) / divisor;
    final level = n < QuoteLabHistoricalService.minimumExploratory
        ? QuoteLabEvidenceLevel.insufficient
        : n >= QuoteLabHistoricalService.minimumIndicative &&
                days.length >= QuoteLabHistoricalService.minimumDistinctDays
            ? QuoteLabEvidenceLevel.needsValidation
            : QuoteLabEvidenceLevel.exploratory;
    return QuoteLabPriceSegment(
      country: country,
      league: league,
      market: market,
      priceBand: band,
      observations: n,
      successes: wins,
      matchDays: days.length,
      hitRatePercent: 100 * p,
      wilsonLower95Percent: 100 * (center - margin).clamp(0.0, 1.0).toDouble(),
      wilsonUpper95Percent: 100 * (center + margin).clamp(0.0, 1.0).toDouble(),
      averagePrice: sumPrices / n,
      averageGrossImpliedPercent: 100 * sumGrossImplied / n,
      averageSmartBetOrDiegoPercent: predictionN == 0
          ? null
          : 100 * sumPrediction / predictionN,
      historicalRoiPercent: 100 * netUnits / n,
      evidenceLevel: level,
    );
  }
}
