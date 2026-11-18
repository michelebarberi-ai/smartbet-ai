import 'dart:math' as math;

import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';

/// Confronto rigorosamente PAIRED: stesse fixture, stesso mercato e stesso
/// esito. I tre motori devono aver registrato una probabilita' prepartita
/// prima di sapere il risultato. Non modifica nessuna previsione live.
class GoalVdLinePairedEngineMetrics {
  final SmartBetAnalysisEngine engine;
  final int sampleSize;
  final int correct;
  final double accuracyPercent;
  final double meanPredictedPercent;
  final double calibrationGapPoints;
  final double brierScore;
  final double logLoss;

  const GoalVdLinePairedEngineMetrics({
    required this.engine,
    required this.sampleSize,
    required this.correct,
    required this.accuracyPercent,
    required this.meanPredictedPercent,
    required this.calibrationGapPoints,
    required this.brierScore,
    required this.logLoss,
  });
}

class GoalVdLinePairedThreeEngineSegment {
  final String country;
  final String league;
  final String market;
  final String thirdInputSource;
  final String thirdModelVersion;
  final int fixtureCount;
  final int distinctMatchDays;
  final List<GoalVdLinePairedEngineMetrics> metrics;

  const GoalVdLinePairedThreeEngineSegment({
    required this.country,
    required this.league,
    required this.market,
    required this.thirdInputSource,
    required this.thirdModelVersion,
    required this.fixtureCount,
    required this.distinctMatchDays,
    required this.metrics,
  });

  GoalVdLinePairedEngineMetrics forEngine(SmartBetAnalysisEngine engine) =>
      metrics.singleWhere((item) => item.engine == engine);

  bool get sufficientEvidence =>
      fixtureCount >= GoalVdLineThreeEnginePairedComparisonService.minimumFixtures &&
      distinctMatchDays >= GoalVdLineThreeEnginePairedComparisonService.minimumDays;

  /// Confronto diagnostico, NON permesso di promuovere il modello live.
  bool get canChangePredictions => false;
}

class GoalVdLinePairedThreeEngineReport {
  final DateTime asOf;
  final DateTime windowStartsAt;
  final int eligibleRecords;
  final int eligibleFixtureMarkets;
  final int pairedFixtureMarkets;
  final int conflictingFixtureMarkets;
  final List<GoalVdLinePairedThreeEngineSegment> segments;

  const GoalVdLinePairedThreeEngineReport({
    required this.asOf,
    required this.windowStartsAt,
    required this.eligibleRecords,
    required this.eligibleFixtureMarkets,
    required this.pairedFixtureMarkets,
    required this.conflictingFixtureMarkets,
    required this.segments,
  });

  int get researchReadySegments =>
      segments.where((s) => s.sufficientEvidence).length;
}

/// Unica popolazione comune per SmartBet, Diego e terzo cervello.
/// Un evento viene confrontato solo se tutti e tre hanno lo stesso mercato,
/// la stessa fixture, lo stesso punteggio reale e lo stesso kickoff.
/// Se tutti prevedono Goal, l'accuratezza binaria e' necessariamente uguale:
/// Brier e log loss misurano la differenza tra le probabilita' assegnate.
class GoalVdLineThreeEnginePairedComparisonService {
  const GoalVdLineThreeEnginePairedComparisonService();

  static const int windowDays = 365;
  static const int minimumFixtures = 100;
  static const int minimumDays = 14;
  static const Duration minimumLead = Duration(minutes: 2);
  static const double _epsilon = 1e-12;

  GoalVdLinePairedThreeEngineReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final start = cutoff.subtract(const Duration(days: windowDays));
    final candidates = <String, Map<SmartBetAnalysisEngine, SmartBetAnalysisRecord>>{};
    final invalidKeys = <String>{};
    var eligible = 0;

    for (final r in records) {
      if (!_eligible(r, start, cutoff)) continue;
      eligible++;
      final market = normalizeAnalysisMarket(r.market);
      final key = '${r.fixtureId}|$market';
      if (invalidKeys.contains(key)) continue;
      final engines = candidates.putIfAbsent(
        key, () => <SmartBetAnalysisEngine, SmartBetAnalysisRecord>{},
      );
      final previous = engines[r.engine];
      if (previous == null) {
        engines[r.engine] = r;
      } else if (!_sameSnapshot(previous, r)) {
        // An ambiguous fixture+market+engine is excluded, not overwritten.
        invalidKeys.add(key);
        candidates.remove(key);
      }
    }

    final buckets = <String, _ThreeEngineBucket>{};
    var paired = 0;
    for (final entry in candidates.entries) {
      if (invalidKeys.contains(entry.key)) continue;
      final trio = entry.value;
      if (trio.length != SmartBetAnalysisEngine.values.length ||
          !SmartBetAnalysisEngine.values.every(trio.containsKey)) {
        continue;
      }
      final first = trio[SmartBetAnalysisEngine.smartBet]!;
      final diego = trio[SmartBetAnalysisEngine.diego]!;
      final third = trio[SmartBetAnalysisEngine.thirdBrain]!;
      if (!_sameFixtureOutcome(first, diego) ||
          !_sameFixtureOutcome(first, third)) {
        continue;
      }
      final source = third.inputSource?.trim() ?? '';
      final version = third.modelVersion?.trim() ?? '';
      if (source.isEmpty || version.isEmpty) continue;

      final market = normalizeAnalysisMarket(first.market);
      final country = _label(first.country);
      final league = _label(first.league);
      final key = '$country|$league|$market|$source|$version';
      final bucket = buckets.putIfAbsent(
        key, () => _ThreeEngineBucket(
          country: country,
          league: league,
          market: market,
          thirdInputSource: source,
          thirdModelVersion: version,
        ),
      );
      bucket.add(trio);
      paired++;
    }

    final segments = buckets.values.map((b) => b.report()).toList()
      ..sort((a, b) {
        final byCount = b.fixtureCount.compareTo(a.fixtureCount);
        if (byCount != 0) return byCount;
        return '${a.league}|${a.market}|${a.thirdModelVersion}'
            .compareTo('${b.league}|${b.market}|${b.thirdModelVersion}');
      });

    return GoalVdLinePairedThreeEngineReport(
      asOf: cutoff,
      windowStartsAt: start,
      eligibleRecords: eligible,
      eligibleFixtureMarkets: candidates.length,
      pairedFixtureMarkets: paired,
      conflictingFixtureMarkets: invalidKeys.length,
      segments: List.unmodifiable(segments),
    );
  }

  bool _eligible(
    SmartBetAnalysisRecord r,
    DateTime start,
    DateTime cutoff,
  ) {
    final kickoff = r.matchDate.toUtc();
    final firstSeen = r.firstSeenAt.toUtc();
    final known = r.outcomeKnownBy?.toUtc();
    final p = r.probability;
    final h = r.actualHomeGoals;
    final a = r.actualAwayGoals;
    if (!r.prospectiveEligible ||
        r.fixtureId <= 0 ||
        _label(r.country).isEmpty ||
        _label(r.league).isEmpty ||
        kickoff.isBefore(start) || kickoff.isAfter(cutoff) ||
        firstSeen.isAfter(kickoff.subtract(minimumLead)) ||
        known == null || !known.isAfter(kickoff) ||
        known.isAfter(cutoff) ||
        p == null || !p.isFinite || p < 0 || p > 1 ||
        h == null || a == null || h < 0 || a < 0 ||
        r.asianSettlement != null ||
        (r.status != SmartBetAnalysisStatus.correct &&
            r.status != SmartBetAnalysisStatus.wrong)) {
      return false;
    }
    final settled = SmartBetAnalysisMarketSettlement.evaluate(
      market: r.market,
      homeGoals: h,
      awayGoals: a,
    );
    return (r.status == SmartBetAnalysisStatus.correct &&
            settled == SmartBetAnalysisSettlement.correct) ||
        (r.status == SmartBetAnalysisStatus.wrong &&
            settled == SmartBetAnalysisSettlement.wrong);
  }

  bool _sameSnapshot(
    SmartBetAnalysisRecord a,
    SmartBetAnalysisRecord b,
  ) =>
      _sameFixtureOutcome(a, b) &&
      a.probability == b.probability &&
      a.firstSeenAt.toUtc().isAtSameMomentAs(b.firstSeenAt.toUtc()) &&
      a.inputSource == b.inputSource &&
      a.modelVersion == b.modelVersion;

  bool _sameFixtureOutcome(
    SmartBetAnalysisRecord a,
    SmartBetAnalysisRecord b,
  ) =>
      a.fixtureId == b.fixtureId &&
      normalizeAnalysisMarket(a.market) == normalizeAnalysisMarket(b.market) &&
      _label(a.country) == _label(b.country) &&
      _label(a.league) == _label(b.league) &&
      a.matchDate.toUtc().isAtSameMomentAs(b.matchDate.toUtc()) &&
      a.actualHomeGoals == b.actualHomeGoals &&
      a.actualAwayGoals == b.actualAwayGoals &&
      a.status == b.status;
}

String _label(String s) =>
    s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

class _ThreeEngineBucket {
  final String country;
  final String league;
  final String market;
  final String thirdInputSource;
  final String thirdModelVersion;
  final Set<String> days = <String>{};
  final Map<SmartBetAnalysisEngine, _MetricAccumulator> accumulator = {
    for (final engine in SmartBetAnalysisEngine.values)
      engine: _MetricAccumulator(),
  };

  _ThreeEngineBucket({
    required this.country,
    required this.league,
    required this.market,
    required this.thirdInputSource,
    required this.thirdModelVersion,
  });

  void add(Map<SmartBetAnalysisEngine, SmartBetAnalysisRecord> trio) {
    final first = trio[SmartBetAnalysisEngine.smartBet]!;
    days.add(first.matchDate.toUtc().toIso8601String().substring(0, 10));
    for (final engine in SmartBetAnalysisEngine.values) {
      final record = trio[engine]!;
      accumulator[engine]!.add(
        record.probability!,
        record.status == SmartBetAnalysisStatus.correct,
      );
    }
  }

  GoalVdLinePairedThreeEngineSegment report() =>
      GoalVdLinePairedThreeEngineSegment(
        country: country,
        league: league,
        market: market,
        thirdInputSource: thirdInputSource,
        thirdModelVersion: thirdModelVersion,
        fixtureCount: accumulator[SmartBetAnalysisEngine.smartBet]!.count,
        distinctMatchDays: days.length,
        metrics: List.unmodifiable([
          for (final engine in SmartBetAnalysisEngine.values)
            accumulator[engine]!.build(engine),
        ]),
      );
}

class _MetricAccumulator {
  int count = 0;
  int correct = 0;
  double sumProbability = 0;
  double sumBrier = 0;
  double sumLogLoss = 0;

  void add(double p, bool hit) {
    final y = hit ? 1.0 : 0.0;
    final safe = p.clamp(GoalVdLineThreeEnginePairedComparisonService._epsilon,
        1 - GoalVdLineThreeEnginePairedComparisonService._epsilon).toDouble();
    count++;
    if (hit) correct++;
    sumProbability += p;
    final error = p - y;
    sumBrier += error * error;
    sumLogLoss += -(y * math.log(safe) +
        (1 - y) * math.log(1 - safe));
  }

  GoalVdLinePairedEngineMetrics build(SmartBetAnalysisEngine engine) {
    final accuracy = count == 0 ? 0.0 : 100.0 * correct / count;
    final mean = count == 0 ? 0.0 : 100.0 * sumProbability / count;
    return GoalVdLinePairedEngineMetrics(
      engine: engine,
      sampleSize: count,
      correct: correct,
      accuracyPercent: accuracy,
      meanPredictedPercent: mean,
      calibrationGapPoints: accuracy - mean,
      brierScore: count == 0 ? 0.0 : sumBrier / count,
      logLoss: count == 0 ? 0.0 : sumLogLoss / count,
    );
  }
}
