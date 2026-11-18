import 'smartbet_analysis_history_store.dart';
import 'smartbet_league_market_reliability_service.dart';

/// Indice di affidabilita storica sperimentale (ex idea "MEI").
/// Non e' la probabilita del prossimo incontro, non usa quote o ROI
/// e non conferisce permessi a calibrazione/trial/live.
class SmartBetMarketEaseIndex {
  final SmartBetLeagueMarketReliability evidence;
  final double? score;
  final String status;
  final double? overconfidencePenalty;
  final double? brierPenalty;

  const SmartBetMarketEaseIndex({
    required this.evidence,
    required this.score,
    required this.status,
    required this.overconfidencePenalty,
    required this.brierPenalty,
  });

  bool get usableForResearch => score != null;
}

class SmartBetMarketEaseIndexReport {
  final DateTime asOf;
  final DateTime windowStartsAt;
  final int uniqueEligibleRecords;
  final List<SmartBetMarketEaseIndex> segments;

  const SmartBetMarketEaseIndexReport({
    required this.asOf,
    required this.windowStartsAt,
    required this.uniqueEligibleRecords,
    required this.segments,
  });

  int get measurableSegments => segments.where((s) => s.score != null).length;
}

/// Solo lettura e nessuna chiamata ai provider esterni.
/// Il servizio di affidabilita esistente e' l'unica fonte di Wilson,
/// deduplica fixture, Brier e calibrazione.
class SmartBetMarketEaseIndexService {
  const SmartBetMarketEaseIndexService();

  static const int minimumFixtures = 100;
  static const int minimumMatchDays = 14;
  static const int windowDays = 365;

  SmartBetMarketEaseIndexReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final windowStart = cutoff.subtract(const Duration(days: windowDays));
    final withinWindow = records.where((record) {
      final kickoff = record.matchDate.toUtc();
      return !kickoff.isBefore(windowStart) && !kickoff.isAfter(cutoff);
    });

    final reliability = const SmartBetLeagueMarketReliabilityService().evaluate(
      records: withinWindow,
      asOf: cutoff,
    );
    final entries = [
      for (final segment in reliability.segments) _fromEvidence(segment),
    ]..sort((a, b) {
      // Only eligible scores are ranked; incomplete groups remain visible
      // below, never falsely displayed as "0% reliability".
      if (a.score == null && b.score != null) return 1;
      if (a.score != null && b.score == null) return -1;
      if (a.score != null && b.score != null) {
        final c = b.score!.compareTo(a.score!);
        if (c != 0) return c;
      }
      final c = b.evidence.sampleSize.compareTo(a.evidence.sampleSize);
      if (c != 0) return c;
      final l = a.evidence.league.compareTo(b.evidence.league);
      if (l != 0) return l;
      final m = a.evidence.market.compareTo(b.evidence.market);
      return m != 0 ? m : a.evidence.engine.name.compareTo(b.evidence.engine.name);
    });

    return SmartBetMarketEaseIndexReport(
      asOf: cutoff,
      windowStartsAt: windowStart,
      uniqueEligibleRecords: reliability.uniqueEligibleRecords,
      segments: List.unmodifiable(entries),
    );
  }

  SmartBetMarketEaseIndex _fromEvidence(
    SmartBetLeagueMarketReliability segment,
  ) {
    final n = segment.sampleSize;
    final days = segment.distinctMatchDays;
    final validProbabilities = segment.probabilitySampleSize;
    final gap = segment.calibrationGapPoints;
    final brier = segment.brierScore;

    // Fully observed probability samples, not a selected subset of wins.
    // "Strong" in existing evidence requires >= 200; >= 100 only
    // permits diagnostic research, not action on live predictions.
    String? missing;
    if (n < minimumFixtures) {
      missing = 'Servono almeno 100 incontri distinti.';
    } else if (days < minimumMatchDays) {
      missing = 'Servono almeno 14 giornate distinte.';
    } else if (validProbabilities != n || gap == null || brier == null ||
        !gap.isFinite || !brier.isFinite || brier < 0 || brier > 1) {
      missing = 'Probabilita prepartita e risultati incompleti.';
    }
    if (missing != null) {
      return SmartBetMarketEaseIndex(
        evidence: segment,
        score: null,
        status: missing,
        overconfidencePenalty: null,
        brierPenalty: null,
      );
    }

    // Il limite Wilson inferiore e' la base conservativa, non una
    // probabilita futura. Penalita trasparente per overconfidence:
    // gap = accuratezza - probabilita media; gap negativo => stima alta.
    final overconfidence = (-gap!).clamp(0.0, 20.0).toDouble() * 0.5;

    // Brier vs riferimento costante che predice la frequenza osservata.
    // Un punteggio peggiore riceve malus; uno migliore NON ottiene bonus
    // in-sample: evitato il premio a un fitting non ancora validato.
    final prevalence = segment.observedAccuracyPercent / 100.0;
    final constantBrier = prevalence * (1.0 - prevalence);
    final poorBrier = (brier! - constantBrier).clamp(0.0, 1.0).toDouble() * 50;

    final score = (segment.wilsonLower95Percent -
            overconfidence - poorBrier)
        .clamp(0.0, 100.0)
        .toDouble();
    return SmartBetMarketEaseIndex(
      evidence: segment,
      score: score,
      status: 'Indice sperimentale: sola diagnostica, non validato live.',
      overconfidencePenalty: overconfidence,
      brierPenalty: poorBrier,
    );
  }
}
