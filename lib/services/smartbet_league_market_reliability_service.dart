import 'dart:math' as math;

import 'smartbet_analysis_history_store.dart';

/// P21W: READ-ONLY evidence for real outcomes by country/league/market/engine.
///
/// This report must never select a coupon, change a prediction or promote
/// calibration weights. Training with the evidence requires a separate,
/// prospective SHADOW validation gate.
enum SmartBetLeagueMarketEvidenceLevel {
  insufficient,
  exploratory,
  signal,
  strongShadowCandidate,
}

class SmartBetLeagueMarketReliability {
  final SmartBetAnalysisEngine engine;
  final String country;
  final String league;
  final String market;
  final int sampleSize;
  final int correct;
  final int wrong;
  final int distinctMatchDays;
  final int probabilitySampleSize;

  /// These are OBSERVED results, not the probability of winning the next bet.
  final double observedAccuracyPercent;
  final double wilsonLower95Percent;
  final double wilsonUpper95Percent;
  final double? averagePredictedPercent;
  final double? calibrationGapPoints;
  final double? brierScore;

  final SmartBetLeagueMarketEvidenceLevel evidenceLevel;

  const SmartBetLeagueMarketReliability({
    required this.engine,
    required this.country,
    required this.league,
    required this.market,
    required this.sampleSize,
    required this.correct,
    required this.wrong,
    required this.distinctMatchDays,
    required this.probabilitySampleSize,
    required this.observedAccuracyPercent,
    required this.wilsonLower95Percent,
    required this.wilsonUpper95Percent,
    required this.averagePredictedPercent,
    required this.calibrationGapPoints,
    required this.brierScore,
    required this.evidenceLevel,
  });

  bool get readyForShadowResearch =>
      evidenceLevel == SmartBetLeagueMarketEvidenceLevel.signal ||
      evidenceLevel == SmartBetLeagueMarketEvidenceLevel.strongShadowCandidate;
}

class SmartBetLeagueMarketReliabilityReport {
  final DateTime asOf;
  final int uniqueEligibleRecords;
  final int skippedUnsafeRecords;
  final int duplicateRecords;
  final int conflictingFixtureMarkets;
  final List<SmartBetLeagueMarketReliability> segments;

  const SmartBetLeagueMarketReliabilityReport({
    required this.asOf,
    required this.uniqueEligibleRecords,
    required this.skippedUnsafeRecords,
    required this.duplicateRecords,
    required this.conflictingFixtureMarkets,
    required this.segments,
  });

  /// No data is not evidence of low (or high) reliability.
  SmartBetLeagueMarketReliability? find({
    required SmartBetAnalysisEngine engine,
    required String country,
    required String league,
    required String market,
  }) {
    final c = _normalizedLabel(country);
    final l = _normalizedLabel(league);
    final m = normalizeAnalysisMarket(market);
    for (final segment in segments) {
      if (segment.engine == engine &&
          segment.country == c &&
          segment.league == l &&
          segment.market == m) {
        return segment;
      }
    }
    return null;
  }
}

class SmartBetLeagueMarketReliabilityService {
  const SmartBetLeagueMarketReliabilityService();

  static const int minimumExploratoryFixtures = 50;
  static const int minimumSignalFixtures = 100;
  static const int minimumStrongFixtures = 200;
  static const int minimumDistinctMatchDays = 14;

  SmartBetLeagueMarketReliabilityReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final deduped = <String, SmartBetAnalysisRecord>{};
    final conflicts = <String>{};
    var skipped = 0;
    var duplicates = 0;

    for (final r in records) {
      final kickoff = r.matchDate.toUtc();
      final firstSeen = r.firstSeenAt.toUtc();
      final knownAt = r.outcomeKnownBy?.toUtc();
      final market = normalizeAnalysisMarket(r.market);
      final country = _normalizedLabel(r.country);
      final league = _normalizedLabel(r.league);
      final p = r.probability;
      final isSettled = r.status == SmartBetAnalysisStatus.correct ||
          r.status == SmartBetAnalysisStatus.wrong;

      if (!r.prospectiveEligible ||
          !isSettled ||
          r.fixtureId <= 0 ||
          market.isEmpty ||
          country.isEmpty ||
          league.isEmpty ||
          !firstSeen.isBefore(kickoff) ||
          kickoff.isAfter(cutoff) ||
          knownAt == null ||
          !knownAt.isAfter(kickoff) ||
          knownAt.isAfter(cutoff) ||
          (p != null && (!p.isFinite || p < 0 || p > 1))) {
        skipped++;
        continue;
      }

      // One vote per fixture + engine + normalized market, regardless of
      // how often the same prediction appears in multiple app screens.
      final key = r.engine.name + '|' + r.fixtureId.toString() + '|' + market;
      if (conflicts.contains(key)) continue;
      final previous = deduped[key];
      if (previous == null) {
        deduped[key] = r;
      } else if (previous.status != r.status ||
          !previous.matchDate.toUtc().isAtSameMomentAs(kickoff) ||
          _normalizedLabel(previous.country) != country ||
          _normalizedLabel(previous.league) != league ||
          previous.probability != r.probability ||
          previous.actualHomeGoals != r.actualHomeGoals ||
          previous.actualAwayGoals != r.actualAwayGoals) {
        // Conflicting outcomes or predictions are not usable evidence.
        deduped.remove(key);
        conflicts.add(key);
      } else {
        duplicates++;
      }
    }

    final buckets = <String, _Bucket>{};
    for (final r in deduped.values) {
      final country = _normalizedLabel(r.country);
      final league = _normalizedLabel(r.league);
      final market = normalizeAnalysisMarket(r.market);
      final key = r.engine.name + '|' + country + '|' + league + '|' + market;
      final bucket = buckets.putIfAbsent(
        key,
        () => _Bucket(r.engine, country, league, market),
      );
      bucket.add(r);
    }

    final segments = buckets.values.map((b) => b.build()).toList()
      ..sort((a, b) {
        final n = b.sampleSize.compareTo(a.sampleSize);
        if (n != 0) return n;
        final c = a.country.compareTo(b.country);
        if (c != 0) return c;
        final l = a.league.compareTo(b.league);
        if (l != 0) return l;
        final m = a.market.compareTo(b.market);
        if (m != 0) return m;
        return a.engine.index.compareTo(b.engine.index);
      });

    return SmartBetLeagueMarketReliabilityReport(
      asOf: cutoff,
      uniqueEligibleRecords: deduped.length,
      skippedUnsafeRecords: skipped,
      duplicateRecords: duplicates,
      conflictingFixtureMarkets: conflicts.length,
      segments: List.unmodifiable(segments),
    );
  }
}

String _normalizedLabel(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

class _Bucket {
  final SmartBetAnalysisEngine engine;
  final String country;
  final String league;
  final String market;
  final Set<String> matchDays = <String>{};
  int total = 0;
  int correct = 0;
  int probabilitySamples = 0;
  int probabilityHits = 0;
  double probabilitySum = 0;
  double brierSum = 0;

  _Bucket(this.engine, this.country, this.league, this.market);

  void add(SmartBetAnalysisRecord r) {
    total++;
    final hit = r.status == SmartBetAnalysisStatus.correct;
    if (hit) correct++;
    matchDays.add(r.matchDate.toUtc().toIso8601String().substring(0, 10));
    final p = r.probability;
    if (p == null) return;
    probabilitySamples++;
    if (hit) probabilityHits++;
    probabilitySum += p;
    final delta = p - (hit ? 1.0 : 0.0);
    brierSum += delta * delta;
  }

  SmartBetLeagueMarketReliability build() {
    final accuracy = 100 * correct / total;
    final interval = _wilsonInterval(correct, total);
    final mean = probabilitySamples == 0
        ? null : 100 * probabilitySum / probabilitySamples;
    final gap = mean == null
        ? null : 100 * probabilityHits / probabilitySamples - mean;

    final SmartBetLeagueMarketEvidenceLevel level;
    if (total < SmartBetLeagueMarketReliabilityService.minimumExploratoryFixtures ||
        matchDays.length < SmartBetLeagueMarketReliabilityService.minimumDistinctMatchDays) {
      level = SmartBetLeagueMarketEvidenceLevel.insufficient;
    } else if (total >= SmartBetLeagueMarketReliabilityService.minimumStrongFixtures) {
      level = SmartBetLeagueMarketEvidenceLevel.strongShadowCandidate;
    } else if (total >= SmartBetLeagueMarketReliabilityService.minimumSignalFixtures) {
      level = SmartBetLeagueMarketEvidenceLevel.signal;
    } else {
      level = SmartBetLeagueMarketEvidenceLevel.exploratory;
    }
    return SmartBetLeagueMarketReliability(
      engine: engine,
      country: country,
      league: league,
      market: market,
      sampleSize: total,
      correct: correct,
      wrong: total - correct,
      distinctMatchDays: matchDays.length,
      probabilitySampleSize: probabilitySamples,
      observedAccuracyPercent: accuracy,
      wilsonLower95Percent: interval.$1,
      wilsonUpper95Percent: interval.$2,
      averagePredictedPercent: mean,
      calibrationGapPoints: gap,
      brierScore: probabilitySamples == 0
          ? null : brierSum / probabilitySamples,
      evidenceLevel: level,
    );
  }
}

/// 95% Wilson confidence interval for an observed binary success rate.
/// Unlike p +/- 1.96 sqrt(p(1-p)/n), remains bounded for 0/n and n/n.
(double, double) _wilsonInterval(int successes, int count) {
  const z = 1.959963984540054;
  final n = count.toDouble();
  final p = successes / n;
  final zz = z * z;
  final denominator = 1 + zz / n;
  final center = (p + zz / (2 * n)) / denominator;
  final margin = z * math.sqrt(p * (1 - p) / n + zz / (4 * n * n)) / denominator;
  return (
    (100 * (center - margin)).clamp(0.0, 100.0).toDouble(),
    (100 * (center + margin)).clamp(0.0, 100.0).toDouble(),
  );
}
