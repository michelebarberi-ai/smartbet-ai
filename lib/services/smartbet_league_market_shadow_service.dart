import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';

/// P21W.4: retrospective, point-in-time SHADOW replay.
/// No predictions, coupon picks, stored history or live weights are modified.
class SmartBetLeagueMarketShadowSegment {
  final SmartBetAnalysisEngine engine;
  final String country;
  final String league;
  final String market;
  final int eligibleFixtures;
  final int evaluatedFixtures;
  final int distinctValidationDays;
  final double? originalBrier;
  final double? shadowBrier;
  final double? meanAdjustmentPoints;

  const SmartBetLeagueMarketShadowSegment({
    required this.engine,
    required this.country,
    required this.league,
    required this.market,
    required this.eligibleFixtures,
    required this.evaluatedFixtures,
    required this.distinctValidationDays,
    required this.originalBrier,
    required this.shadowBrier,
    required this.meanAdjustmentPoints,
  });

  double? get brierImprovement => originalBrier == null || shadowBrier == null
      ? null : originalBrier! - shadowBrier!;

  /// An exploratory flag, NOT statistical significance or live activation.
  bool get warrantsFurtherResearch =>
      evaluatedFixtures >= SmartBetLeagueMarketShadowService.minimumValidationFixtures &&
      distinctValidationDays >= SmartBetLeagueMarketShadowService.minimumValidationDays &&
      (brierImprovement ?? 0) > 0.005;
}

class SmartBetLeagueMarketShadowReport {
  final DateTime asOf;
  final int rejectedRecords;
  final int duplicateRecords;
  final int conflictingFixtureMarkets;
  final List<SmartBetLeagueMarketShadowSegment> segments;

  const SmartBetLeagueMarketShadowReport({
    required this.asOf,
    required this.rejectedRecords,
    required this.duplicateRecords,
    required this.conflictingFixtureMarkets,
    required this.segments,
  });
}

/// Replays an offline prospective correction: each prediction can use only
/// settled results that were known BEFORE its original firstSeenAt.
/// The original prediction and its recorded outcome remain immutable.
/// No prices, odds, network access or storage are used.
class SmartBetLeagueMarketShadowService {
  const SmartBetLeagueMarketShadowService();

  static const int minimumTrainingFixtures = 50;
  static const int minimumValidationFixtures = 30;
  static const int minimumValidationDays = 10;

  SmartBetLeagueMarketShadowReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final unique = <String, SmartBetAnalysisRecord>{};
    final conflicts = <String>{};
    var rejected = 0;
    var duplicates = 0;

    for (final record in records) {
      if (!_eligible(record, cutoff)) {
        rejected++;
        continue;
      }
      final key = '${record.engine.name}|${record.fixtureId}|${normalizeAnalysisMarket(record.market)}';
      if (conflicts.contains(key)) continue;
      final previous = unique[key];
      if (previous == null) {
        unique[key] = record;
      } else if (!_samePredictionAndOutcome(previous, record)) {
        unique.remove(key);
        conflicts.add(key);
      } else {
        duplicates++;
      }
    }

    final groups = <String, List<SmartBetAnalysisRecord>>{};
    for (final record in unique.values) {
      final key = '${record.engine.name}|${_label(record.country)}|${_label(record.league)}|${normalizeAnalysisMarket(record.market)}';
      groups.putIfAbsent(key, () => <SmartBetAnalysisRecord>[]).add(record);
    }

    final results = <SmartBetLeagueMarketShadowSegment>[];
    for (final group in groups.values) {
      final first = group.first;
      final chronological = group.toList()
        ..sort((a, b) {
          final order = a.firstSeenAt.compareTo(b.firstSeenAt);
          return order != 0 ? order : a.fixtureId.compareTo(b.fixtureId);
        });
      final known = group.toList()
        ..sort((a, b) {
          final order = a.outcomeKnownBy!.compareTo(b.outcomeKnownBy!);
          return order != 0 ? order : a.fixtureId.compareTo(b.fixtureId);
        });

      var cursor = 0;
      var trained = 0;
      var sumPredicted = 0.0;
      var sumObserved = 0.0;
      var evaluated = 0;
      var originalError = 0.0;
      var shadowError = 0.0;
      var adjustmentSum = 0.0;
      final validationDays = <String>{};

      for (final target in chronological) {
        final predictionTime = target.firstSeenAt.toUtc();
        while (cursor < known.length &&
            known[cursor].outcomeKnownBy!.toUtc().isBefore(predictionTime)) {
          final prior = known[cursor++];
          trained++;
          sumPredicted += prior.probability!;
          sumObserved += prior.status == SmartBetAnalysisStatus.correct ? 1 : 0;
        }

        if (trained < minimumTrainingFixtures) continue;

        final gap = (sumObserved - sumPredicted) / trained;
        final shrinkage = trained / (trained + 100.0);
        final delta = (gap * shrinkage).clamp(-0.10, 0.10).toDouble();
        final original = target.probability!;
        final corrected = (original + delta).clamp(0.01, 0.99).toDouble();
        final result = target.status == SmartBetAnalysisStatus.correct ? 1.0 : 0.0;
        final e1 = original - result;
        final e2 = corrected - result;
        originalError += e1 * e1;
        shadowError += e2 * e2;
        adjustmentSum += 100 * delta;
        evaluated++;
        validationDays.add(target.matchDate.toUtc().toIso8601String().substring(0, 10));
      }

      results.add(SmartBetLeagueMarketShadowSegment(
        engine: first.engine,
        country: _label(first.country),
        league: _label(first.league),
        market: normalizeAnalysisMarket(first.market),
        eligibleFixtures: group.length,
        evaluatedFixtures: evaluated,
        distinctValidationDays: validationDays.length,
        originalBrier: evaluated == 0 ? null : originalError / evaluated,
        shadowBrier: evaluated == 0 ? null : shadowError / evaluated,
        meanAdjustmentPoints: evaluated == 0 ? null : adjustmentSum / evaluated,
      ));
    }

    results.sort((a, b) {
      final count = b.evaluatedFixtures.compareTo(a.evaluatedFixtures);
      if (count != 0) return count;
      final country = a.country.compareTo(b.country);
      if (country != 0) return country;
      final league = a.league.compareTo(b.league);
      if (league != 0) return league;
      final market = a.market.compareTo(b.market);
      return market != 0 ? market : a.engine.index.compareTo(b.engine.index);
    });

    return SmartBetLeagueMarketShadowReport(
      asOf: cutoff,
      rejectedRecords: rejected,
      duplicateRecords: duplicates,
      conflictingFixtureMarkets: conflicts.length,
      segments: List.unmodifiable(results),
    );
  }

  bool _eligible(SmartBetAnalysisRecord r, DateTime cutoff) {
    final firstSeen = r.firstSeenAt.toUtc();
    final kickoff = r.matchDate.toUtc();
    final known = r.outcomeKnownBy?.toUtc();
    final p = r.probability;
    if (r.actualHomeGoals == null || r.actualAwayGoals == null) return false;
    final settlement = SmartBetAnalysisMarketSettlement.evaluate(
      market: r.market,
      homeGoals: r.actualHomeGoals!,
      awayGoals: r.actualAwayGoals!,
    );
    // Never train on unverified, unsupported or conflicting labels.
    if (settlement == SmartBetAnalysisSettlement.unsupported ||
        (r.status == SmartBetAnalysisStatus.correct && settlement != SmartBetAnalysisSettlement.correct) ||
        (r.status == SmartBetAnalysisStatus.wrong && settlement != SmartBetAnalysisSettlement.wrong)) {
      return false;
    }
    return r.prospectiveEligible &&
        r.fixtureId > 0 &&
        _label(r.country).isNotEmpty &&
        _label(r.league).isNotEmpty &&
        normalizeAnalysisMarket(r.market).isNotEmpty &&
        r.asianSettlement == null &&
        (r.status == SmartBetAnalysisStatus.correct ||
            r.status == SmartBetAnalysisStatus.wrong) &&
        r.actualHomeGoals != null &&
        r.actualAwayGoals != null &&
        r.actualHomeGoals! >= 0 &&
        r.actualAwayGoals! >= 0 &&
        p != null &&
        p.isFinite &&
        p >= 0 &&
        p <= 1 &&
        firstSeen.isBefore(kickoff) &&
        !kickoff.isAfter(cutoff) &&
        known != null &&
        known.isAfter(kickoff) &&
        !known.isAfter(cutoff);
  }

  bool _samePredictionAndOutcome(SmartBetAnalysisRecord a, SmartBetAnalysisRecord b) =>
      a.engine == b.engine &&
      a.fixtureId == b.fixtureId &&
      _label(a.country) == _label(b.country) &&
      _label(a.league) == _label(b.league) &&
      a.matchDate.toUtc().isAtSameMomentAs(b.matchDate.toUtc()) &&
      a.firstSeenAt.toUtc().isAtSameMomentAs(b.firstSeenAt.toUtc()) &&
      a.outcomeKnownBy!.toUtc().isAtSameMomentAs(b.outcomeKnownBy!.toUtc()) &&
      a.probability == b.probability &&
      a.status == b.status &&
      a.actualHomeGoals == b.actualHomeGoals &&
      a.actualAwayGoals == b.actualAwayGoals;
}

String _label(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');
