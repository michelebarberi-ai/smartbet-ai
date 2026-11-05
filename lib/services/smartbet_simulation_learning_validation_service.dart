import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';
import 'smartbet_simulation_shadow_store.dart';

/// P21G: esperimenti OFFLINE su probabilita' catturate prima del match.
/// Non ricalcola partite, non cambia quote, mercati, schedine o storico.
enum SmartBetSimulationLearningDecision {
  insufficientData,
  noTrainingAdvantage,
  validationFailed,
  trialCandidate,
}

class SmartBetSimulationLearningMarketResult {
  final String engine;
  final String market;
  final String modelVersion;
  final SmartBetSimulationLearningDecision decision;
  final int eligibleCases;
  final int trainingCases;
  final int validationCases;
  final int lowQualityCases;
  final int trainingDays;
  final int validationDays;
  final double? candidateSimulationWeight;
  final double? trainingOriginalBrier;
  final double? trainingCandidateBrier;
  final double? validationOriginalBrier;
  final double? validationCandidateBrier;
  final double? firstValidationHalfImprovement;
  final double? secondValidationHalfImprovement;

  const SmartBetSimulationLearningMarketResult({
    required this.engine,
    required this.market,
    required this.modelVersion,
    required this.decision,
    required this.eligibleCases,
    required this.trainingCases,
    required this.validationCases,
    required this.lowQualityCases,
    required this.trainingDays,
    required this.validationDays,
    required this.candidateSimulationWeight,
    required this.trainingOriginalBrier,
    required this.trainingCandidateBrier,
    required this.validationOriginalBrier,
    required this.validationCandidateBrier,
    required this.firstValidationHalfImprovement,
    required this.secondValidationHalfImprovement,
  });

  bool get trialSuggested =>
      decision == SmartBetSimulationLearningDecision.trialCandidate;

  double? get validationImprovement =>
      validationOriginalBrier == null || validationCandidateBrier == null
      ? null
      : validationOriginalBrier! - validationCandidateBrier!;

  Map<String, Object?> toJson() => {
    'engine': engine,
    'market': market,
    'modelVersion': modelVersion,
    'decision': decision.name,
    'eligibleCases': eligibleCases,
    'trainingCases': trainingCases,
    'validationCases': validationCases,
    'lowQualityCases': lowQualityCases,
    'trainingDays': trainingDays,
    'validationDays': validationDays,
    'candidateSimulationWeight': candidateSimulationWeight,
    'trainingOriginalBrier': trainingOriginalBrier,
    'trainingCandidateBrier': trainingCandidateBrier,
    'validationOriginalBrier': validationOriginalBrier,
    'validationCandidateBrier': validationCandidateBrier,
    'validationImprovement': validationImprovement,
    'firstValidationHalfImprovement': firstValidationHalfImprovement,
    'secondValidationHalfImprovement': secondValidationHalfImprovement,
    'trialSuggested': trialSuggested,
  };
}

class SmartBetSimulationLearningReport {
  final int totalSnapshots;
  final int pendingSnapshots;
  final int conflictingSnapshots;
  final int invalidSnapshots;
  final int duplicateSnapshots;
  final int unmatchedPairs;
  final int unsupportedPairs;
  final List<SmartBetSimulationLearningMarketResult> markets;

  const SmartBetSimulationLearningReport({
    required this.totalSnapshots,
    required this.pendingSnapshots,
    required this.conflictingSnapshots,
    required this.invalidSnapshots,
    required this.duplicateSnapshots,
    required this.unmatchedPairs,
    required this.unsupportedPairs,
    required this.markets,
  });

  int get trialCandidates => markets.where((m) => m.trialSuggested).length;

  Map<String, Object?> toJson() => {
    'schema': 'smartbet_p21g_shadow_validation_v1',
    'mode': 'shadow_only',
    'totalSnapshots': totalSnapshots,
    'pendingSnapshots': pendingSnapshots,
    'conflictingSnapshots': conflictingSnapshots,
    'invalidSnapshots': invalidSnapshots,
    'duplicateSnapshots': duplicateSnapshots,
    'unmatchedPairs': unmatchedPairs,
    'unsupportedPairs': unsupportedPairs,
    'trialCandidates': trialCandidates,
    'markets': markets.map((m) => m.toJson()).toList(),
  };
}

/// Le combinazioni candidate sono predefinite per evitare ricerca arbitraria
/// di parametri sul periodo di validazione. I dati di validazione NON vengono
/// mai usati per scegliere il peso.
class SmartBetSimulationLearningValidationService {
  final SmartBetSimulationShadowStore _shadow;
  final SmartBetAnalysisHistoryStore _history;

  const SmartBetSimulationLearningValidationService({
    required SmartBetSimulationShadowStore shadowStore,
    required SmartBetAnalysisHistoryStore historyStore,
  }) : _shadow = shadowStore,
       _history = historyStore;

  static const int minimumTrainingFixtures = 60;
  static const int minimumValidationFixtures = 40;
  static const int minimumTrainingDays = 10;
  static const int minimumValidationDays = 7;
  static const double minimumTrainingGain = 0.002;
  static const double minimumValidationGain = 0.002;
  static const double minimumHalfGain = 0.0005;
  static const List<double> candidateWeights = [0.25, 0.5, 0.75, 1.0];

  Future<SmartBetSimulationLearningReport> evaluateStored({
    DateTime? asOf,
  }) async {
    await _history.initialize();
    await _shadow.initialize();
    return evaluate(
      snapshots: _shadow.snapshots,
      history: _history.records,
      asOf: asOf ?? DateTime.now(),
    );
  }

  /// Il risultato finale deve essere gia' noto al momento asOf.
  /// Per ogni test holdout si apprendono i pesi SOLO da risultati risolti
  /// prima della prima previsione holdout, impedendo look-ahead bias.
  SmartBetSimulationLearningReport evaluate({
    required Iterable<SmartBetSimulationShadowSnapshot> snapshots,
    required Iterable<SmartBetAnalysisRecord> history,
    required DateTime asOf,
  }) {
    final now = asOf.toUtc();
    final outcomes = <int, _KnownFixture>{};
    final conflicts = <int>{};

    for (final record in history) {
      final h = record.actualHomeGoals;
      final a = record.actualAwayGoals;
      final resolved = record.resolvedAt?.toUtc();
      final kickoff = record.matchDate.toUtc();
      if (record.fixtureId <= 0 ||
          h == null ||
          a == null ||
          h < 0 ||
          a < 0 ||
          !record.prospectiveEligible ||
          !record.firstSeenAt.toUtc().isBefore(kickoff) ||
          record.status == SmartBetAnalysisStatus.pending ||
          resolved == null ||
          !resolved.isAfter(kickoff) ||
          resolved.isAfter(now)) {
        continue;
      }
      final previous = outcomes[record.fixtureId];
      if (previous != null &&
          (previous.home != h ||
              previous.away != a ||
              previous.kickoff != kickoff)) {
        conflicts.add(record.fixtureId);
      } else if (previous == null || resolved.isBefore(previous.resolved)) {
        outcomes[record.fixtureId] = _KnownFixture(kickoff, resolved, h, a);
      }
    }

    final grouped = <String, List<_LearningExample>>{};
    final seen = <String>{};
    var total = 0;
    var pending = 0;
    var conflicting = 0;
    var invalid = 0;
    var duplicate = 0;
    var unmatched = 0;
    var unsupported = 0;

    for (final snapshot in snapshots) {
      total++;
      final engine = snapshot.engine.trim().toUpperCase();
      final unique = '$engine|${snapshot.fixtureId}';
      if (!seen.add(unique)) {
        duplicate++;
        continue;
      }
      if (conflicts.contains(snapshot.fixtureId)) {
        conflicting++;
        continue;
      }
      final outcome = outcomes[snapshot.fixtureId];
      if (outcome == null) {
        pending++;
        continue;
      }
      final captured = snapshot.capturedAt.toUtc();
      if (snapshot.matchDate.toUtc() != outcome.kickoff ||
          !captured.isBefore(outcome.kickoff) ||
          captured.isAfter(now)) {
        invalid++;
        continue;
      }
      final original = snapshot.originalProbabilities;
      final simulated = snapshot.simulatedProbabilities;
      final keys = <String>{...original.keys, ...simulated.keys};
      for (final rawMarket in keys) {
        final p = original[rawMarket];
        final s = simulated[rawMarket];
        if (p == null || s == null) {
          unmatched++;
          continue;
        }
        if (!p.isFinite || !s.isFinite || p < 0 || p > 1 || s < 0 || s > 1) {
          unsupported++;
          continue;
        }
        final market = rawMarket.trim().toUpperCase();
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
        final key = '$engine|$market|${snapshot.modelVersion}';
        (grouped[key] ??= []).add(
          _LearningExample(
            fixtureId: snapshot.fixtureId,
            captured: captured,
            resolved: outcome.resolved,
            original: p,
            simulated: s,
            actual: actual,
            lowQuality: snapshot.dataQuality < 0.6,
          ),
        );
      }
    }

    final results = <SmartBetSimulationLearningMarketResult>[];
    for (final entry in grouped.entries) {
      final key = entry.key.split('|');
      final values = entry.value
        ..sort((a, b) {
          final cmp = a.captured.compareTo(b.captured);
          return cmp != 0 ? cmp : a.fixtureId.compareTo(b.fixtureId);
        });
      results.add(
        _evaluateMarket(
          engine: key[0],
          market: key[1],
          modelVersion: key.sublist(2).join('|'),
          cases: values,
        ),
      );
    }
    results.sort((a, b) {
      final engine = a.engine.compareTo(b.engine);
      if (engine != 0) return engine;
      final market = a.market.compareTo(b.market);
      return market != 0 ? market : a.modelVersion.compareTo(b.modelVersion);
    });

    return SmartBetSimulationLearningReport(
      totalSnapshots: total,
      pendingSnapshots: pending,
      conflictingSnapshots: conflicting,
      invalidSnapshots: invalid,
      duplicateSnapshots: duplicate,
      unmatchedPairs: unmatched,
      unsupportedPairs: unsupported,
      markets: List.unmodifiable(results),
    );
  }

  SmartBetSimulationLearningMarketResult _evaluateMarket({
    required String engine,
    required String market,
    required String modelVersion,
    required List<_LearningExample> cases,
  }) {
    final cutoffIndex = (cases.length * 0.6).floor();
    // Non mescolare partite catturate allo stesso istante tra i due periodi.
    final cutoff = cutoffIndex < cases.length
        ? cases[cutoffIndex].captured
        : cases.last.captured;
    final training = cases
        .where(
          (c) => c.captured.isBefore(cutoff) && c.resolved.isBefore(cutoff),
        )
        .toList();
    final validation = cases
        .where((c) => !c.captured.isBefore(cutoff))
        .toList();
    final trainDays = _distinctDays(training);
    final validDays = _distinctDays(validation);
    final enough =
        training.length >= minimumTrainingFixtures &&
        validation.length >= minimumValidationFixtures &&
        trainDays >= minimumTrainingDays &&
        validDays >= minimumValidationDays &&
        training.map((c) => c.fixtureId).toSet().length == training.length &&
        validation.map((c) => c.fixtureId).toSet().length == validation.length;

    SmartBetSimulationLearningDecision decision =
        SmartBetSimulationLearningDecision.insufficientData;
    double? selectedWeight;
    double? trainOriginal;
    double? trainCandidate;
    double? validOriginal;
    double? validCandidate;
    double? firstImprovement;
    double? secondImprovement;

    if (enough) {
      trainOriginal = _brier(training, 0);
      // Il peso migliore e' selezionato SOLO sul training.
      double bestScore = trainOriginal;
      for (final weight in candidateWeights) {
        final score = _brier(training, weight);
        if (score < bestScore - 1e-12) {
          bestScore = score;
          selectedWeight = weight;
        }
      }
      if (selectedWeight == null ||
          trainOriginal - bestScore < minimumTrainingGain) {
        decision = SmartBetSimulationLearningDecision.noTrainingAdvantage;
      } else {
        trainCandidate = bestScore;
        validOriginal = _brier(validation, 0);
        validCandidate = _brier(validation, selectedWeight);
        final halfway = validation.length ~/ 2;
        firstImprovement =
            _brier(validation.sublist(0, halfway), 0) -
            _brier(validation.sublist(0, halfway), selectedWeight);
        secondImprovement =
            _brier(validation.sublist(halfway), 0) -
            _brier(validation.sublist(halfway), selectedWeight);
        if (validOriginal - validCandidate >= minimumValidationGain &&
            firstImprovement >= minimumHalfGain &&
            secondImprovement >= minimumHalfGain) {
          decision = SmartBetSimulationLearningDecision.trialCandidate;
        } else {
          decision = SmartBetSimulationLearningDecision.validationFailed;
        }
      }
    }

    return SmartBetSimulationLearningMarketResult(
      engine: engine,
      market: market,
      modelVersion: modelVersion,
      decision: decision,
      eligibleCases: cases.length,
      trainingCases: training.length,
      validationCases: validation.length,
      lowQualityCases: cases.where((c) => c.lowQuality).length,
      trainingDays: trainDays,
      validationDays: validDays,
      candidateSimulationWeight: selectedWeight,
      trainingOriginalBrier: trainOriginal,
      trainingCandidateBrier: trainCandidate,
      validationOriginalBrier: validOriginal,
      validationCandidateBrier: validCandidate,
      firstValidationHalfImprovement: firstImprovement,
      secondValidationHalfImprovement: secondImprovement,
    );
  }

  static int _distinctDays(List<_LearningExample> cases) => cases
      .map((c) {
        final date = c.captured;
        return '${date.year}-${date.month}-${date.day}';
      })
      .toSet()
      .length;

  static double _brier(List<_LearningExample> cases, double simWeight) {
    var sum = 0.0;
    for (final e in cases) {
      final p = e.original * (1 - simWeight) + e.simulated * simWeight;
      final delta = p - e.actual;
      sum += delta * delta;
    }
    return sum / cases.length;
  }
}

class _KnownFixture {
  final DateTime kickoff;
  final DateTime resolved;
  final int home;
  final int away;
  const _KnownFixture(this.kickoff, this.resolved, this.home, this.away);
}

class _LearningExample {
  final int fixtureId;
  final DateTime captured;
  final DateTime resolved;
  final double original;
  final double simulated;
  final double actual;
  final bool lowQuality;
  const _LearningExample({
    required this.fixtureId,
    required this.captured,
    required this.resolved,
    required this.original,
    required this.simulated,
    required this.actual,
    required this.lowQuality,
  });
}
