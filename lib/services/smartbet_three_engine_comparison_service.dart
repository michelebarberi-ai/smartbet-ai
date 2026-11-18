import 'smartbet_analysis_history_store.dart';

/// B66: strictly descriptive pairwise comparisons on identical fixtures and
/// market outcomes. Inputs may be shared: the simulator is NOT independent
/// confirmation of SmartBet or Diego.
class SmartBetThreeEngineMarketComparison {
  final String market;
  final int pairedWithSmartBet;
  final int pairedWithDiego;
  final int completeTriplets;
  final int distinctSmartBetDays;
  final int distinctDiegoDays;
  final double? smartBetBrier;
  final double? simulatorOnSmartBetFixturesBrier;
  final double? diegoBrier;
  final double? simulatorOnDiegoFixturesBrier;
  final int simulatorSharedSmartBetInputs;
  final int simulatorSharedDiegoInputs;

  const SmartBetThreeEngineMarketComparison({
    required this.market,
    required this.pairedWithSmartBet,
    required this.pairedWithDiego,
    required this.completeTriplets,
    required this.distinctSmartBetDays,
    required this.distinctDiegoDays,
    required this.smartBetBrier,
    required this.simulatorOnSmartBetFixturesBrier,
    required this.diegoBrier,
    required this.simulatorOnDiegoFixturesBrier,
    required this.simulatorSharedSmartBetInputs,
    required this.simulatorSharedDiegoInputs,
  });

  bool get smartBetResearchSample =>
      pairedWithSmartBet >= 30 && distinctSmartBetDays >= 10;

  bool get diegoResearchSample =>
      pairedWithDiego >= 30 && distinctDiegoDays >= 10;

  /// Positive means the simulator had lower Brier error in the paired sample.
  double? get advantageVsSmartBet =>
      smartBetBrier == null || simulatorOnSmartBetFixturesBrier == null
          ? null : smartBetBrier! - simulatorOnSmartBetFixturesBrier!;

  double? get advantageVsDiego =>
      diegoBrier == null || simulatorOnDiegoFixturesBrier == null
          ? null : diegoBrier! - simulatorOnDiegoFixturesBrier!;
}

class SmartBetThreeEngineComparisonReport {
  final int includedForecastRecords;
  final int rejectedForecastRecords;
  final int conflictingFixtureMarkets;
  final List<SmartBetThreeEngineMarketComparison> markets;

  const SmartBetThreeEngineComparisonReport({
    required this.includedForecastRecords,
    required this.rejectedForecastRecords,
    required this.conflictingFixtureMarkets,
    required this.markets,
  });
}

class SmartBetThreeEngineComparisonService {
  const SmartBetThreeEngineComparisonService();

  SmartBetThreeEngineComparisonReport evaluate({
    required Iterable<SmartBetAnalysisRecord> records,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final groups = <String, Map<SmartBetAnalysisEngine, SmartBetAnalysisRecord>>{};
    final conflicting = <String>{};
    var rejected = 0;
    var accepted = 0;

    for (final record in records) {
      // Meta AI is an ensemble outcome, not one of its own source engines.
      if (record.engine == SmartBetAnalysisEngine.metaAi) continue;
      final market = normalizeAnalysisMarket(record.market);
      final known = record.outcomeKnownBy?.toUtc();
      final start = record.matchDate.toUtc();
      final observedAt = record.firstSeenAt.toUtc();
      final p = record.probability;
      if (!record.prospectiveEligible || !record.hasActualResult ||
          record.asianSettlement != null || record.fixtureId <= 0 ||
          market.isEmpty || p == null || !p.isFinite || p < 0 || p > 1 ||
          !observedAt.isBefore(start) ||
          record.status != SmartBetAnalysisStatus.correct &&
              record.status != SmartBetAnalysisStatus.wrong ||
          known == null || !known.isAfter(start) ||
          known.isAfter(cutoff) || start.isAfter(cutoff) ||
          (record.engine == SmartBetAnalysisEngine.diego &&
              record.qualified != true) ||
          (record.engine == SmartBetAnalysisEngine.simulator &&
              !{'SIMULATOR_XG_FROM_SMARTBET', 'SIMULATOR_XG_FROM_DIEGO'}
                  .contains(record.classification))) {
        rejected++;
        continue;
      }

      final key = '${record.fixtureId}|${record.country.trim()}|'
          '${record.league.trim()}|$market';
      if (conflicting.contains(key)) continue;
      final perEngine = groups.putIfAbsent(key, () => {});
      final existing = perEngine[record.engine];
      if (existing != null &&
          (existing.status != record.status ||
           existing.probability != record.probability ||
           existing.actualHomeGoals != record.actualHomeGoals ||
           existing.actualAwayGoals != record.actualAwayGoals ||
           !existing.matchDate.toUtc().isAtSameMomentAs(start))) {
        groups.remove(key);
        conflicting.add(key);
        continue;
      }
      perEngine[record.engine] = record;
      accepted++;
    }

    final buckets = <String, _ThreeEngineBucket>{};
    for (final perEngine in groups.values) {
      final simulator = perEngine[SmartBetAnalysisEngine.simulator];
      if (simulator == null) continue;
      final smartBet = perEngine[SmartBetAnalysisEngine.smartBet];
      final diego = perEngine[SmartBetAnalysisEngine.diego];
      if (smartBet == null && diego == null) continue;
      final smartValid = smartBet != null && _sameOutcome(simulator, smartBet);
      final diegoValid = diego != null && _sameOutcome(simulator, diego);
      // A contradictory outcome is not a valid pair. Do not render an
      // empty market bucket as though a real comparison existed.
      if (!smartValid && !diegoValid) continue;
      final market = normalizeAnalysisMarket(simulator.market);
      final bucket = buckets.putIfAbsent(market, () => _ThreeEngineBucket());
      if (smartValid) bucket.addSmartBet(simulator, smartBet);
      if (diegoValid) bucket.addDiego(simulator, diego);
      if (smartValid && diegoValid) bucket.triplets++;
    }

    final report = buckets.entries.map((entry) =>
        entry.value.build(entry.key)).toList()
      ..sort((a, b) {
        final n = (b.pairedWithSmartBet + b.pairedWithDiego)
            .compareTo(a.pairedWithSmartBet + a.pairedWithDiego);
        return n != 0 ? n : a.market.compareTo(b.market);
      });

    return SmartBetThreeEngineComparisonReport(
      includedForecastRecords: accepted,
      rejectedForecastRecords: rejected,
      conflictingFixtureMarkets: conflicting.length,
      markets: List.unmodifiable(report),
    );
  }

  bool _sameOutcome(
    SmartBetAnalysisRecord a,
    SmartBetAnalysisRecord b,
  ) => a.status == b.status &&
       a.actualHomeGoals == b.actualHomeGoals &&
       a.actualAwayGoals == b.actualAwayGoals &&
       a.matchDate.toUtc().isAtSameMomentAs(b.matchDate.toUtc());
}

class _ThreeEngineBucket {
  int smartCount = 0;
  int diegoCount = 0;
  int triplets = 0;
  int sharedSmartBet = 0;
  int sharedDiego = 0;
  double smartBrierSum = 0;
  double thirdSmartBrierSum = 0;
  double diegoBrierSum = 0;
  double thirdDiegoBrierSum = 0;
  final smartDays = <String>{};
  final diegoDays = <String>{};

  double _loss(SmartBetAnalysisRecord r) {
    final observed = r.status == SmartBetAnalysisStatus.correct ? 1.0 : 0.0;
    final error = r.probability! - observed;
    return error * error;
  }

  void addSmartBet(SmartBetAnalysisRecord simulator,
                   SmartBetAnalysisRecord smartBet) {
    smartCount++;
    smartBrierSum += _loss(smartBet);
    thirdSmartBrierSum += _loss(simulator);
    smartDays.add(simulator.matchDate.toUtc().toIso8601String().substring(0, 10));
    if (simulator.classification == 'SIMULATOR_XG_FROM_SMARTBET') {
      sharedSmartBet++;
    }
  }

  void addDiego(SmartBetAnalysisRecord simulator,
                SmartBetAnalysisRecord diego) {
    diegoCount++;
    diegoBrierSum += _loss(diego);
    thirdDiegoBrierSum += _loss(simulator);
    diegoDays.add(simulator.matchDate.toUtc().toIso8601String().substring(0, 10));
    if (simulator.classification == 'SIMULATOR_XG_FROM_DIEGO') {
      sharedDiego++;
    }
  }

  SmartBetThreeEngineMarketComparison build(String market) =>
      SmartBetThreeEngineMarketComparison(
        market: market,
        pairedWithSmartBet: smartCount,
        pairedWithDiego: diegoCount,
        completeTriplets: triplets,
        distinctSmartBetDays: smartDays.length,
        distinctDiegoDays: diegoDays.length,
        smartBetBrier: smartCount > 0 ? smartBrierSum / smartCount : null,
        simulatorOnSmartBetFixturesBrier:
            smartCount > 0 ? thirdSmartBrierSum / smartCount : null,
        diegoBrier: diegoCount > 0 ? diegoBrierSum / diegoCount : null,
        simulatorOnDiegoFixturesBrier:
            diegoCount > 0 ? thirdDiegoBrierSum / diegoCount : null,
        simulatorSharedSmartBetInputs: sharedSmartBet,
        simulatorSharedDiegoInputs: sharedDiego,
      );
}
