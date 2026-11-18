import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';

/// Historical, strictly paired audit: identical fixture/country/league/market,
/// verified final score and prospective prediction from each parent and meta.
/// A lower Brier is not proof of future superiority or permission for live use.
class GoalVdLineFourthBrainValidationReport {
  final int completeTriplets;
  final int distinctMatchDays;
  final int rejected;
  final int conflicts;
  final double? smartBetBrier;
  final double? diegoBrier;
  final double? metaBrier;

  const GoalVdLineFourthBrainValidationReport({
    required this.completeTriplets,
    required this.distinctMatchDays,
    required this.rejected,
    required this.conflicts,
    required this.smartBetBrier,
    required this.diegoBrier,
    required this.metaBrier,
  });

  bool get exploratorySample => completeTriplets >= 30 &&
      distinctMatchDays >= 10;
  bool get researchSample => completeTriplets >= 100 &&
      distinctMatchDays >= 14;

  /// Positive = Meta AI Brier is below BOTH parents on the paired sample.
  /// Descriptive only; cannot authorize deployment.
  double? get marginBelowBestParent {
    if (smartBetBrier == null || diegoBrier == null || metaBrier == null) {
      return null;
    }
    final best = smartBetBrier! < diegoBrier!
        ? smartBetBrier! : diegoBrier!;
    return best - metaBrier!;
  }
}

class GoalVdLineFourthBrainValidationService {
  const GoalVdLineFourthBrainValidationService();

  GoalVdLineFourthBrainValidationReport evaluate({
    required Iterable<SmartBetAnalysisRecord> history,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final grouped =
        <String, Map<SmartBetAnalysisEngine, SmartBetAnalysisRecord>>{};
    final conflicts = <String>{};
    var rejected = 0;

    for (final record in history) {
      // The mathematical simulator itself is NOT independent.
      if (record.engine == SmartBetAnalysisEngine.simulator) continue;

      final market = normalizeAnalysisMarket(record.market);
      final known = record.outcomeKnownBy?.toUtc();
      final kickoff = record.matchDate.toUtc();
      final seen = record.firstSeenAt.toUtc();
      final p = record.probability;
      final h = record.actualHomeGoals;
      final a = record.actualAwayGoals;
      final correct = record.status == SmartBetAnalysisStatus.correct;
      final wrong = record.status == SmartBetAnalysisStatus.wrong;
      final settled = h == null || a == null ? null
          : SmartBetAnalysisMarketSettlement.evaluate(
              market: market, homeGoals: h, awayGoals: a,
            );
      if (!record.prospectiveEligible ||
          !seen.isBefore(kickoff) || kickoff.isAfter(cutoff) ||
          known == null || !known.isAfter(kickoff) ||
          known.isAfter(cutoff) ||
          record.fixtureId <= 0 || record.country.trim().isEmpty ||
          record.league.trim().isEmpty || market.isEmpty ||
          p == null || !p.isFinite || p < 0 || p > 1 ||
          (!correct && !wrong) ||
          (correct && settled != SmartBetAnalysisSettlement.correct) ||
          (wrong && settled != SmartBetAnalysisSettlement.wrong) ||
          (record.engine == SmartBetAnalysisEngine.diego &&
              record.qualified != true) ||
          (record.engine == SmartBetAnalysisEngine.metaAi &&
              !(record.classification ?? '').startsWith('META_B67_V1_SHADOW_'))) {
        rejected++;
        continue;
      }

      final key = '${record.fixtureId}|${record.country.trim()}|'
          '${record.league.trim()}|$market';
      if (conflicts.contains(key)) continue;
      final group = grouped.putIfAbsent(key, () => {});
      final previous = group[record.engine];
      if (previous != null &&
          (previous.probability != record.probability ||
              previous.status != record.status ||
              previous.matchDate.toUtc() != kickoff ||
              previous.actualHomeGoals != h ||
              previous.actualAwayGoals != a)) {
        grouped.remove(key);
        conflicts.add(key);
        continue;
      }
      group[record.engine] = record;
    }

    var count = 0;
    var smartSum = 0.0;
    var diegoSum = 0.0;
    var metaSum = 0.0;
    final days = <String>{};
    for (final group in grouped.values) {
      final smart = group[SmartBetAnalysisEngine.smartBet];
      final diego = group[SmartBetAnalysisEngine.diego];
      final meta = group[SmartBetAnalysisEngine.metaAi];
      if (smart == null || diego == null || meta == null) continue;
      // Ensure no conflicting fixture scores, outcomes or kickoff.
      if (smart.status != diego.status || smart.status != meta.status ||
          smart.actualHomeGoals != diego.actualHomeGoals ||
          smart.actualHomeGoals != meta.actualHomeGoals ||
          smart.actualAwayGoals != diego.actualAwayGoals ||
          smart.actualAwayGoals != meta.actualAwayGoals ||
          smart.matchDate.toUtc() != diego.matchDate.toUtc() ||
          smart.matchDate.toUtc() != meta.matchDate.toUtc()) {
        continue;
      }
      final actual = smart.status == SmartBetAnalysisStatus.correct
          ? 1.0 : 0.0;
      double brier(SmartBetAnalysisRecord r) {
        final delta = r.probability! - actual;
        return delta * delta;
      }
      count++;
      smartSum += brier(smart);
      diegoSum += brier(diego);
      metaSum += brier(meta);
      days.add(smart.matchDate.toUtc().toIso8601String().substring(0, 10));
    }

    return GoalVdLineFourthBrainValidationReport(
      completeTriplets: count,
      distinctMatchDays: days.length,
      rejected: rejected,
      conflicts: conflicts.length,
      smartBetBrier: count == 0 ? null : smartSum / count,
      diegoBrier: count == 0 ? null : diegoSum / count,
      metaBrier: count == 0 ? null : metaSum / count,
    );
  }
}
