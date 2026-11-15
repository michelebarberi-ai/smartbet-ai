import 'smartbet_analysis_history_store.dart';
import 'smartbet_simulation_shadow_store.dart';
import 'goalvdline_minute_replay_service.dart';

/// B54 - audit *read-only* dei replay temporali con risultati reali risolti.
///
/// Usa soltanto xG e probabilità già CONGELATI prima del kickoff: non
/// interroga i provider, non ricalcola statistiche storiche e non aggiorna
/// quote, schedine o policy di apprendimento.
class GoalVdLineReplayValidationMetric {
  final String engine;
  final String market;
  final int fixtures;
  final int matchDays;
  final double originalBrier;
  final double priorSimulatorBrier;
  final double minuteReplayBrier;
  final double firstHalfDifference;
  final double secondHalfDifference;

  const GoalVdLineReplayValidationMetric({
    required this.engine,
    required this.market,
    required this.fixtures,
    required this.matchDays,
    required this.originalBrier,
    required this.priorSimulatorBrier,
    required this.minuteReplayBrier,
    required this.firstHalfDifference,
    required this.secondHalfDifference,
  });

  /// Positivo: replay minore Brier. Non implica efficacia provata.
  double get improvement => priorSimulatorBrier - minuteReplayBrier;

  bool get enoughObservations =>
      fixtures >= GoalVdLineReplayValidationService.minimumFixtures &&
      matchDays >= GoalVdLineReplayValidationService.minimumDays;

  /// Segnale esplorativo: mai autorizzazione alla produzione.
  bool get exploratoryPositive =>
      enoughObservations &&
      improvement >= GoalVdLineReplayValidationService.minimumBrierGain &&
      firstHalfDifference > 0 &&
      secondHalfDifference > 0;
}

class GoalVdLineReplayValidationReport {
  final int sourceSnapshots;
  final int eligibleSnapshots;
  final int pendingResults;
  final int duplicateSnapshots;
  final int contradictoryResults;
  final int invalidSnapshots;
  final int insufficientQuality;
  final int unmatchedMarkets;
  final List<GoalVdLineReplayValidationMetric> metrics;

  const GoalVdLineReplayValidationReport({
    required this.sourceSnapshots,
    required this.eligibleSnapshots,
    required this.pendingResults,
    required this.duplicateSnapshots,
    required this.contradictoryResults,
    required this.invalidSnapshots,
    required this.insufficientQuality,
    required this.unmatchedMarkets,
    required this.metrics,
  });

  int get exploratorySignals =>
      metrics.where((m) => m.exploratoryPositive).length;

  /// Nessuna decisione di promozione viene mai prodotta dal report.
  bool get changesOfficialPredictions => false;
}

class GoalVdLineReplayValidationService {
  const GoalVdLineReplayValidationService({
    this.replay = const GoalVdLineMinuteReplayService(),
  });

  final GoalVdLineMinuteReplayService replay;
  static const int minimumFixtures = 100;
  static const int minimumDays = 14;
  static const double minimumDataQuality = 0.65;
  static const double minimumBrierGain = 0.002;
  static const int replaySimulations = 5000;

  Future<GoalVdLineReplayValidationReport> evaluateStored({
    DateTime? asOf,
  }) async {
    final shadow = SmartBetSimulationShadowStore.instance;
    final history = SmartBetAnalysisHistoryStore.instance;
    await shadow.initialize();
    await history.initialize();
    return evaluate(
      snapshots: shadow.snapshots,
      history: history.records,
      asOf: asOf ?? DateTime.now(),
    );
  }

  GoalVdLineReplayValidationReport evaluate({
    required Iterable<SmartBetSimulationShadowSnapshot> snapshots,
    required Iterable<SmartBetAnalysisRecord> history,
    required DateTime asOf,
  }) {
    final end = asOf.toUtc();
    final outcomes = <int, _ResolvedFixture>{};
    final conflicting = <int>{};

    for (final record in history) {
      final h = record.actualHomeGoals;
      final a = record.actualAwayGoals;
      final kickoff = record.matchDate.toUtc();
      final resolved = record.resolvedAt?.toUtc();
      if (record.fixtureId <= 0 ||
          !record.prospectiveEligible ||
          !record.firstSeenAt.toUtc().isBefore(kickoff) ||
          (record.status != SmartBetAnalysisStatus.correct &&
              record.status != SmartBetAnalysisStatus.wrong) ||
          h == null ||
          a == null ||
          h < 0 ||
          a < 0 ||
          resolved == null ||
          !resolved.isAfter(kickoff) ||
          resolved.isAfter(end)) {
        continue;
      }
      final previous = outcomes[record.fixtureId];
      final next = _ResolvedFixture(kickoff, h, a);
      if (previous != null &&
          (previous.kickoff != next.kickoff ||
              previous.home != next.home ||
              previous.away != next.away)) {
        conflicting.add(record.fixtureId);
      } else {
        outcomes.putIfAbsent(record.fixtureId, () => next);
      }
    }

    final source = snapshots.toList(growable: false);
    final seen = <String>{};
    final rows = <String, List<_ComparedRow>>{};
    var eligible = 0;
    var pending = 0;
    var duplicates = 0;
    var conflicts = 0;
    var invalid = 0;
    var lowQuality = 0;
    var unmatched = 0;

    for (final snapshot in source) {
      final engine = snapshot.engine.trim().toUpperCase();
      final key = '$engine|${snapshot.fixtureId}';
      if (!seen.add(key)) {
        duplicates++;
        continue;
      }
      if (conflicting.contains(snapshot.fixtureId)) {
        conflicts++;
        continue;
      }
      final outcome = outcomes[snapshot.fixtureId];
      if (outcome == null) {
        pending++;
        continue;
      }
      final kickoff = snapshot.matchDate.toUtc();
      if (engine.isEmpty ||
          !snapshot.capturedAt.toUtc().isBefore(kickoff) ||
          snapshot.capturedAt.toUtc().isAfter(end) ||
          kickoff != outcome.kickoff ||
          snapshot.expectedHomeGoals <= 0 ||
          snapshot.expectedAwayGoals <= 0 ||
          snapshot.expectedHomeGoals > 6 ||
          snapshot.expectedAwayGoals > 6 ||
          !snapshot.expectedHomeGoals.isFinite ||
          !snapshot.expectedAwayGoals.isFinite) {
        invalid++;
        continue;
      }
      if (snapshot.dataQuality < minimumDataQuality) {
        lowQuality++;
        continue;
      }
      final simulated = replay.simulate(
        fixtureId: snapshot.fixtureId,
        expectedHomeGoals: snapshot.expectedHomeGoals,
        expectedAwayGoals: snapshot.expectedAwayGoals,
        simulations: replaySimulations,
      );
      eligible++;
      for (final entry in simulated.probabilities.entries) {
        final market = entry.key;
        final previous = snapshot.simulatedProbabilities[market];
        final official = snapshot.originalProbabilities[market];
        if (previous == null ||
            official == null ||
            !previous.isFinite ||
            !official.isFinite ||
            previous < 0 ||
            previous > 1 ||
            official < 0 ||
            official > 1) {
          unmatched++;
          continue;
        }
        final happened = _occurred(market, outcome.home, outcome.away);
        if (happened == null) continue;
        final y = happened ? 1.0 : 0.0;
        rows.putIfAbsent('$engine|$market', () => []).add(_ComparedRow(
          kickoff: kickoff,
          fixtureId: snapshot.fixtureId,
          original: _brier(official, y),
          previous: _brier(previous, y),
          replay: _brier(entry.value, y),
        ));
      }
    }

    final metrics = <GoalVdLineReplayValidationMetric>[];
    for (final entry in rows.entries) {
      final items = entry.value
        ..sort((a, b) {
          final byDate = a.kickoff.compareTo(b.kickoff);
          return byDate != 0 ? byDate : a.fixtureId.compareTo(b.fixtureId);
        });
      final halves = items.length ~/ 2;
      final keyParts = entry.key.split('|');
      double avg(Iterable<_ComparedRow> source, double Function(_ComparedRow) f) {
        var n = 0;
        var total = 0.0;
        for (final item in source) {
          n++;
          total += f(item);
        }
        return n == 0 ? 0 : total / n;
      }
      final first = items.take(halves);
      final second = items.skip(halves);
      metrics.add(GoalVdLineReplayValidationMetric(
        engine: keyParts.first,
        market: keyParts.last,
        fixtures: items.length,
        matchDays: items.map((row) => DateTime.utc(
          row.kickoff.year, row.kickoff.month, row.kickoff.day,
        )).toSet().length,
        originalBrier: avg(items, (r) => r.original),
        priorSimulatorBrier: avg(items, (r) => r.previous),
        minuteReplayBrier: avg(items, (r) => r.replay),
        firstHalfDifference: avg(first, (r) => r.previous - r.replay),
        secondHalfDifference: avg(second, (r) => r.previous - r.replay),
      ));
    }
    metrics.sort((a, b) {
      final count = b.fixtures.compareTo(a.fixtures);
      return count != 0 ? count :
          '${a.engine}|${a.market}'.compareTo('${b.engine}|${b.market}');
    });
    return GoalVdLineReplayValidationReport(
      sourceSnapshots: source.length,
      eligibleSnapshots: eligible,
      pendingResults: pending,
      duplicateSnapshots: duplicates,
      contradictoryResults: conflicts,
      invalidSnapshots: invalid,
      insufficientQuality: lowQuality,
      unmatchedMarkets: unmatched,
      metrics: List.unmodifiable(metrics),
    );
  }

  static double _brier(double p, double y) => (p - y) * (p - y);

  static bool? _occurred(String market, int h, int a) {
    final total = h + a;
    switch (market) {
      case '1': return h > a;
      case 'X': return h == a;
      case '2': return h < a;
      case '1X': return h >= a;
      case 'X2': return h <= a;
      case '12': return h != a;
      case 'GOAL': return h > 0 && a > 0;
      case 'NO GOAL': return h == 0 || a == 0;
      case 'OVER 1.5': return total >= 2;
      case 'UNDER 1.5': return total <= 1;
      case 'OVER 2.5': return total >= 3;
      case 'UNDER 2.5': return total <= 2;
    }
    return null;
  }
}

class _ResolvedFixture {
  final DateTime kickoff;
  final int home;
  final int away;
  const _ResolvedFixture(this.kickoff, this.home, this.away);
}

class _ComparedRow {
  final DateTime kickoff;
  final int fixtureId;
  final double original;
  final double previous;
  final double replay;
  const _ComparedRow({
    required this.kickoff,
    required this.fixtureId,
    required this.original,
    required this.previous,
    required this.replay,
  });
}
