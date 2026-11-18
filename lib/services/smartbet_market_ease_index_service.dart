import 'dart:math' as math;

import 'smartbet_analysis_history_store.dart';
import 'smartbet_league_market_reliability_service.dart';

/// B66: only a historical diagnostic. A MEI score is NOT a probability,
/// a predicted outcome, or permission to change a live coupon.
enum MarketEaseEvidenceStatus {
  insufficient,
  exploratory,
  shadowCandidate,
}

class MarketEaseIndexEntry {
  final SmartBetLeagueMarketReliability evidence;
  final MarketEaseEvidenceStatus status;

  /// 0-100 historical indicator, only when sufficient evidence is available.
  /// Null means unknown, NOT zero or a bad market.
  final double? score;

  /// Brier skill versus a constant forecast at the observed base rate.
  /// Null when the baseline is undefined (all successes or all failures).
  final double? brierSkill;

  /// Percentage points by which predicted probability exceeded reality.
  final double overconfidencePoints;

  const MarketEaseIndexEntry({
    required this.evidence,
    required this.status,
    required this.score,
    required this.brierSkill,
    required this.overconfidencePoints,
  });

  bool get availableForShadowComparison =>
      status == MarketEaseEvidenceStatus.shadowCandidate && score != null;
}

class MarketEaseIndexReport {
  final DateTime asOf;
  final int evaluatedRecords;
  final int excludedBeforeReliability;
  final List<MarketEaseIndexEntry> entries;

  const MarketEaseIndexReport({
    required this.asOf,
    required this.evaluatedRecords,
    required this.excludedBeforeReliability,
    required this.entries,
  });
}

/// The MEI ranks *past* model+country+league+market evidence.
///
/// It must never inspect betting odds, write to persistent stores, apply
/// calibration, rank current fixtures or alter selections. Promotion to a
/// live policy requires a different prospective validation gate.
class SmartBetMarketEaseIndexService {
  const SmartBetMarketEaseIndexService();

  static const int minimumExploratoryFixtures = 50;
  static const int minimumScoredFixtures = 100;
  static const int minimumDistinctDays = 14;

  MarketEaseIndexReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required DateTime asOf,
  }) {
    // Protect this diagnostic against unqualified Diego output,
    // partial Asian settlement and missing actual results.
    // The existing reliability evaluator subsequently handles prospective
    // timing, settlement cutoffs, normalized segments and dedup conflicts.
    final filtered = <SmartBetAnalysisRecord>[];
    var excluded = 0;
    for (final r in records) {
      if (!r.hasActualResult ||
          r.asianSettlement != null ||
          (r.engine == SmartBetAnalysisEngine.diego && r.qualified != true)) {
        excluded++;
        continue;
      }
      filtered.add(r);
    }

    final reliability = const SmartBetLeagueMarketReliabilityService()
        .evaluate(records: filtered, asOf: asOf);
    final entries = <MarketEaseIndexEntry>[];

    for (final segment in reliability.segments) {
      final enoughDays = segment.distinctMatchDays >= minimumDistinctDays;
      final hasCompleteProbabilities =
          segment.probabilitySampleSize == segment.sampleSize &&
          segment.brierScore != null &&
          segment.calibrationGapPoints != null;

      final status = !enoughDays ||
              segment.sampleSize < minimumExploratoryFixtures ||
              !hasCompleteProbabilities
          ? MarketEaseEvidenceStatus.insufficient
          : segment.sampleSize < minimumScoredFixtures
              ? MarketEaseEvidenceStatus.exploratory
              : MarketEaseEvidenceStatus.shadowCandidate;

      // Never substitute a zero score for an unknown value.
      final gap = segment.calibrationGapPoints;
      final overconfidence = math.max(0.0, -(gap ?? 0.0));
      final baseRate = segment.observedAccuracyPercent / 100.0;
      final baselineBrier = baseRate * (1.0 - baseRate);
      final brier = segment.brierScore;

      final double? skill =
          brier == null || baselineBrier <= 0.0
              ? null
              : 1.0 - brier / baselineBrier;

      double? score;
      if (status == MarketEaseEvidenceStatus.shadowCandidate) {
        // Conservative lower bound, penalty for overconfident forecasts,
        // small bounded bonus/malus for skillful probability estimates.
        // All inputs are outcome history; odds have no role here.
        final skillAdjustment =
            skill == null ? 0.0 : 3.0 * skill.clamp(-1.0, 1.0);
        score = (segment.wilsonLower95Percent -
                0.75 * overconfidence +
                skillAdjustment)
            .clamp(0.0, 100.0)
            .toDouble();
      }

      entries.add(MarketEaseIndexEntry(
        evidence: segment,
        status: status,
        score: score,
        brierSkill: skill,
        overconfidencePoints: overconfidence,
      ));
    }

    // Scored evidence first; unscored exploratory/insufficient data last.
    entries.sort((a, b) {
      if (a.score != null && b.score == null) return -1;
      if (a.score == null && b.score != null) return 1;
      if (a.score != null && b.score != null) {
        final byScore = b.score!.compareTo(a.score!);
        if (byScore != 0) return byScore;
      }
      final bySamples = b.evidence.sampleSize.compareTo(a.evidence.sampleSize);
      if (bySamples != 0) return bySamples;
      final byLeague = a.evidence.league.compareTo(b.evidence.league);
      if (byLeague != 0) return byLeague;
      final byMarket = a.evidence.market.compareTo(b.evidence.market);
      if (byMarket != 0) return byMarket;
      return a.evidence.engine.index.compareTo(b.evidence.engine.index);
    });

    return MarketEaseIndexReport(
      asOf: reliability.asOf,
      evaluatedRecords: reliability.uniqueEligibleRecords,
      excludedBeforeReliability: excluded,
      entries: List.unmodifiable(entries),
    );
  }
}
