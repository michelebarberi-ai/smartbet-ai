import 'smartbet_analysis_history_store.dart';
import 'smartbet_choice_trial.dart';
import 'smartbet_analysis_market_settlement.dart';
import 'smartbet_simulation_shadow_store.dart';

/// P21D: confronto retrospettivo (solo lettura) delle probabilita' congelate
/// prima del calcio d'inizio. Non calibra, non chiama API e non modifica lo
/// storico. Ogni confronto e' abbinato per fixture, motore e mercato.
class SmartBetSimulationOutcomeMarketMetric {
  final String engine;
  final String market;
  final int sampleSize;
  final int occurred;
  final double meanOriginalProbability;
  final double meanSimulatedProbability;
  final double observedFrequency;
  final double originalBrier;
  final double simulatedBrier;

  const SmartBetSimulationOutcomeMarketMetric({
    required this.engine,
    required this.market,
    required this.sampleSize,
    required this.occurred,
    required this.meanOriginalProbability,
    required this.meanSimulatedProbability,
    required this.observedFrequency,
    required this.originalBrier,
    required this.simulatedBrier,
  });

  /// Positivo: simulatore migliore sul campione; negativo: peggiore.
  double get brierImprovement => originalBrier - simulatedBrier;

  /// Un campione piccolo NON autorizza ad applicare automaticamente correzioni.
  bool get exploratoryOnly => sampleSize < 50;

  Map<String, Object> toJson() => {
    'engine': engine,
    'market': market,
    'sampleSize': sampleSize,
    'occurred': occurred,
    'meanOriginalProbability': meanOriginalProbability,
    'meanSimulatedProbability': meanSimulatedProbability,
    'observedFrequency': observedFrequency,
    'originalBrier': originalBrier,
    'simulatedBrier': simulatedBrier,
    'brierImprovement': brierImprovement,
    'exploratoryOnly': exploratoryOnly,
  };
}

class SmartBetSimulationOutcomeAuditReport {
  final Map<String, SmartBetChoiceTotals> choices;
  final int snapshotCount;
  final int comparedSnapshots;
  final int pendingSnapshots;
  final int conflictingFixtures;
  final int duplicateSnapshots;
  final int invalidFixtureSnapshots;
  final int unsupportedMarketPairs;
  final int unmatchedMarketPairs;
  final Map<String, SmartBetSimulationOutcomeMarketMetric> metrics;

  const SmartBetSimulationOutcomeAuditReport({
    this.choices = const {},
    required this.snapshotCount,
    required this.comparedSnapshots,
    required this.pendingSnapshots,
    required this.conflictingFixtures,
    required this.duplicateSnapshots,
    required this.invalidFixtureSnapshots,
    required this.unsupportedMarketPairs,
    required this.unmatchedMarketPairs,
    required this.metrics,
  });

  SmartBetSimulationOutcomeMarketMetric? metricFor({
    required String engine,
    required String market,
  }) =>
      metrics['${engine.trim().toUpperCase()}|${market.trim().toUpperCase()}'];

  int get comparedMarketPairs =>
      metrics.values.fold<int>(0, (total, metric) => total + metric.sampleSize);

  Map<String, Object> toJson() => {
    'schema': 'smartbet_p21d_outcome_audit_v1',
    'choiceTrialV1': {for (final e in choices.entries) e.key: e.value.toJson()},
    'snapshotCount': snapshotCount,
    'comparedSnapshots': comparedSnapshots,
    'pendingSnapshots': pendingSnapshots,
    'conflictingFixtures': conflictingFixtures,
    'duplicateSnapshots': duplicateSnapshots,
    'invalidFixtureSnapshots': invalidFixtureSnapshots,
    'unsupportedMarketPairs': unsupportedMarketPairs,
    'unmatchedMarketPairs': unmatchedMarketPairs,
    'comparedMarketPairs': comparedMarketPairs,
    'metrics': {
      for (final entry in metrics.entries) entry.key: entry.value.toJson(),
    },
  };
}

class SmartBetSimulationOutcomeAuditService {
  final SmartBetSimulationShadowStore _shadowStore;
  final SmartBetAnalysisHistoryStore _historyStore;

  SmartBetSimulationOutcomeAuditService({
    SmartBetSimulationShadowStore? shadowStore,
    SmartBetAnalysisHistoryStore? historyStore,
  }) : _shadowStore = shadowStore ?? SmartBetSimulationShadowStore.instance,
       _historyStore = historyStore ?? SmartBetAnalysisHistoryStore.instance;

  /// Legge solo gli store locali, senza avviare alcun fetch dei risultati.
  /// Chiamare dopo il resolver gia' esistente, quando si vuole un nuovo report.
  Future<SmartBetSimulationOutcomeAuditReport> evaluateStored() async {
    await _historyStore.initialize();
    await _shadowStore.initialize();
    return evaluate(
      snapshots: _shadowStore.snapshots,
      history: _historyStore.records,
    );
  }

  /// Utile anche per test e backtest offline: nessun accesso a disco o rete.
  SmartBetSimulationOutcomeAuditReport evaluate({
    required Iterable<SmartBetSimulationShadowSnapshot> snapshots,
    required Iterable<SmartBetAnalysisRecord> history,
  }) {
    final scores = <int, _FixtureOutcome>{};
    final conflicts = <int>{};

    // Una partita puo' avere molti record per mercato e motore. Si deduplica
    // per fixture e si rifiutano risultati finali contraddittori.
    for (final record in history) {
      final h = record.actualHomeGoals;
      final a = record.actualAwayGoals;
      if (record.fixtureId <= 0 ||
          h == null ||
          a == null ||
          h < 0 ||
          a < 0 ||
          record.resolvedAt == null ||
          record.resolvedAt!.toUtc().isBefore(record.matchDate.toUtc()) ||
          record.status == SmartBetAnalysisStatus.pending) {
        continue;
      }
      final candidate = _FixtureOutcome(
        kickoff: record.matchDate.toUtc(),
        home: h,
        away: a,
      );
      final existing = scores[record.fixtureId];
      if (existing == null) {
        scores[record.fixtureId] = candidate;
      } else if (existing.kickoff != candidate.kickoff ||
          existing.home != h ||
          existing.away != a) {
        conflicts.add(record.fixtureId);
      }
    }

    final choices = <String, SmartBetChoiceTotals>{};
    final seen = <String>{};
    final totals = <String, _PairAccumulator>{};
    var snapshotsCount = 0;
    var compared = 0;
    var pending = 0;
    var conflicting = 0;
    var duplicates = 0;
    var invalid = 0;
    var unsupported = 0;
    var unmatched = 0;

    for (final snapshot in snapshots) {
      snapshotsCount++;
      if (!seen.add(snapshot.key)) {
        duplicates++;
        continue;
      }
      if (conflicts.contains(snapshot.fixtureId)) {
        conflicting++;
        continue;
      }
      final outcome = scores[snapshot.fixtureId];
      if (outcome == null) {
        pending++;
        continue;
      }
      if (outcome.kickoff != snapshot.matchDate.toUtc() ||
          !snapshot.capturedAt.toUtc().isBefore(snapshot.matchDate.toUtc())) {
        invalid++;
        continue;
      }

      compared++;
      final official = snapshot.officialChoice;
      final trial = snapshot.trialChoiceV1;
      if (official != null && trial != null) {
        choices.putIfAbsent(snapshot.engine, SmartBetChoiceTotals.new)
            .add(official, trial, outcome.home, outcome.away);
      }
      // Non appaiamo mercati differenti o sconosciuti. Solo l'intersezione
      // delle due mappe e' confrontabile: stesso fixture, motore e mercato.
      final original = snapshot.originalProbabilities;
      final simulated = snapshot.simulatedProbabilities;
      final allMarkets = {...original.keys, ...simulated.keys};
      for (final market in allMarkets) {
        final pOld = original[market];
        final pNew = simulated[market];
        if (pOld == null || pNew == null) {
          unmatched++;
          continue;
        }
        if (!pOld.isFinite ||
            !pNew.isFinite ||
            pOld < 0 ||
            pOld > 1 ||
            pNew < 0 ||
            pNew > 1) {
          unsupported++;
          continue;
        }
        final settlement = SmartBetAnalysisMarketSettlement.evaluate(
          market: market,
          homeGoals: outcome.home,
          awayGoals: outcome.away,
        );
        if (settlement == SmartBetAnalysisSettlement.unsupported) {
          unsupported++;
          continue;
        }
        final actual = settlement == SmartBetAnalysisSettlement.correct
            ? 1.0
            : 0.0;
        final key =
            '${snapshot.engine.trim().toUpperCase()}|${market.trim().toUpperCase()}';
        final acc = totals.putIfAbsent(key, _PairAccumulator.new);
        acc.add(pOld, pNew, actual);
      }
    }

    final metrics = <String, SmartBetSimulationOutcomeMarketMetric>{};
    for (final entry in totals.entries) {
      final divider = entry.key.indexOf('|');
      final acc = entry.value;
      metrics[entry.key] = SmartBetSimulationOutcomeMarketMetric(
        engine: entry.key.substring(0, divider),
        market: entry.key.substring(divider + 1),
        sampleSize: acc.n,
        occurred: acc.occurred,
        meanOriginalProbability: acc.sumOld / acc.n,
        meanSimulatedProbability: acc.sumNew / acc.n,
        observedFrequency: acc.occurred / acc.n,
        originalBrier: acc.oldSquaredError / acc.n,
        simulatedBrier: acc.newSquaredError / acc.n,
      );
    }
    return SmartBetSimulationOutcomeAuditReport(
      choices: Map.unmodifiable(choices),
      snapshotCount: snapshotsCount,
      comparedSnapshots: compared,
      pendingSnapshots: pending,
      conflictingFixtures: conflicting,
      duplicateSnapshots: duplicates,
      invalidFixtureSnapshots: invalid,
      unsupportedMarketPairs: unsupported,
      unmatchedMarketPairs: unmatched,
      metrics: Map.unmodifiable(metrics),
    );
  }
}

class _FixtureOutcome {
  final DateTime kickoff;
  final int home;
  final int away;
  const _FixtureOutcome({
    required this.kickoff,
    required this.home,
    required this.away,
  });
}

class _PairAccumulator {
  int n = 0;
  int occurred = 0;
  double sumOld = 0;
  double sumNew = 0;
  double oldSquaredError = 0;
  double newSquaredError = 0;

  void add(double original, double simulated, double actual) {
    n++;
    occurred += actual.toInt();
    sumOld += original;
    sumNew += simulated;
    oldSquaredError += (original - actual) * (original - actual);
    newSquaredError += (simulated - actual) * (simulated - actual);
  }
}
