import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_scorer_learning_service.dart';

/// A minimal, non-technical public summary.
/// It intentionally excludes legacy retrospective copies and never presents
/// an across-market hit rate as the probability of the next fixture.
class GoalVdLinePublicLearningSummary {
  final int verifiedPredictions;
  final int distinctFixtures;
  final int pendingPredictions;
  final int verifiedMatchDays;
  final int smartBetVerified;
  final int diegoVerified;
  final int smartBetCorrect;
  final int diegoCorrect;
  final int scorerVerified;
  final int scorerScored;

  const GoalVdLinePublicLearningSummary({
    required this.verifiedPredictions,
    required this.distinctFixtures,
    required this.pendingPredictions,
    required this.verifiedMatchDays,
    required this.smartBetVerified,
    required this.diegoVerified,
    this.smartBetCorrect = 0,
    this.diegoCorrect = 0,
    this.scorerVerified = 0,
    this.scorerScored = 0,
  });

  static GoalVdLinePublicLearningSummary fromRecords(
    Iterable<SmartBetAnalysisRecord> records, {
    DateTime? asOf,
    Iterable<SmartBetScorerLearningRecord> scorerRecords = const [],
  }) {
    final now = (asOf ?? DateTime.now()).toUtc();
    final unique = <String>{};
    final fixtureIds = <int>{};
    final matchDays = <String>{};
    var resolved = 0;
    var pending = 0;
    var smartBet = 0;
    var diego = 0;
    var smartBetCorrect = 0;
    var diegoCorrect = 0;
    var scorerVerified = 0;
    var scorerScored = 0;

    for (final r in records) {
      // La Home mantiene i conteggi consolidati SmartBet/Diego.
      // Il terzo cervello viene mostrato solo nella diagnostica dedicata,
      // per non gonfiare le percentuali esistenti con piu' mercati per gara.
      if (r.engine == SmartBetAnalysisEngine.thirdBrain) continue;
      if (!r.prospectiveEligible ||
          r.fixtureId <= 0 ||
          !r.firstSeenAt.toUtc().isBefore(r.matchDate.toUtc()) ||
          r.firstSeenAt.toUtc().isAfter(now)) {
        continue;
      }
      if (!unique.add(r.key)) continue;
      if (r.status == SmartBetAnalysisStatus.pending) {
        if (r.matchDate.toUtc().isAfter(now)) pending++;
        continue;
      }
      if (r.status != SmartBetAnalysisStatus.correct &&
          r.status != SmartBetAnalysisStatus.wrong) {
        continue;
      }
      final known = r.outcomeKnownBy?.toUtc();
      if (known == null ||
          !known.isAfter(r.matchDate.toUtc()) ||
          known.isAfter(now) ||
          r.actualHomeGoals == null ||
          r.actualAwayGoals == null) {
        continue;
      }
      resolved++;
      fixtureIds.add(r.fixtureId);
      matchDays.add(r.matchDate.toUtc().toIso8601String().substring(0, 10));
      if (r.engine == SmartBetAnalysisEngine.smartBet) {
        smartBet++;
        if (r.status == SmartBetAnalysisStatus.correct) smartBetCorrect++;
      }
      if (r.engine == SmartBetAnalysisEngine.diego) {
        diego++;
        if (r.status == SmartBetAnalysisStatus.correct) diegoCorrect++;
      }
    }

    // Marcatori use a separate verified pre-match archive. Never fold
    // its hit rate into the fixture-market accuracy denominators.
    final scorerKeys = <String>{};
    for (final r in scorerRecords) {
      if (!r.isResolved ||
          !r.predictedAt.toUtc().isBefore(r.kickoffAt.toUtc()) ||
          !r.resolvedAt!.toUtc().isAfter(r.kickoffAt.toUtc()) ||
          r.resolvedAt!.toUtc().isAfter(now) ||
          !scorerKeys.add(r.key)) {
        continue;
      }
      scorerVerified++;
      if (r.scored) scorerScored++;
    }
    return GoalVdLinePublicLearningSummary(
      verifiedPredictions: resolved,
      distinctFixtures: fixtureIds.length,
      pendingPredictions: pending,
      verifiedMatchDays: matchDays.length,
      smartBetVerified: smartBet,
      diegoVerified: diego,
      smartBetCorrect: smartBetCorrect,
      diegoCorrect: diegoCorrect,
      scorerVerified: scorerVerified,
      scorerScored: scorerScored,
    );
  }
}

/// Users need reassurance that model performance is checked, not raw audit
/// dashboards, export buttons, token entry or unvalidated percentages.
class GoalVdLinePublicLearningCard extends StatelessWidget {
  const GoalVdLinePublicLearningCard({
    super.key,
    required this.records,
    this.scorerRecords = const [],
    this.asOf,
  });

  final List<SmartBetAnalysisRecord> records;
  final List<SmartBetScorerLearningRecord> scorerRecords;
  /// Injectable cutoff for deterministic tests, defaults to current time.
  final DateTime? asOf;

  Widget _rateColumn({
    required String name,
    required int correct,
    required int verified,
  }) {
    final rate = verified == 0
        ? '—'
        : (100.0 * correct / verified).toStringAsFixed(1) + '%';
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(rate,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )),
          ),
          const SizedBox(height: 3),
          Text(name, maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(verified == 0 ? 'Nessun dato' : 'n=' + verified.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = GoalVdLinePublicLearningSummary.fromRecords(
      records, asOf: asOf, scorerRecords: scorerRecords,
    );
    final hasSample = summary.verifiedPredictions > 0;
    return Card(
      key: const Key('b57-public-learning-card'),
      color: const Color(0xFF1F2937),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_outlined, color: Colors.lightBlueAccent),
                SizedBox(width: 9),
                Expanded(
                  child: Text('Qualità e apprendimento',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'GoalVdLine confronta le previsioni con i risultati reali '
              'per verificare nel tempo la precisione dei suoi modelli.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              hasSample
                  ? '${summary.distinctFixtures} partite concluse '
                    'con ${summary.verifiedPredictions} pronostici '
                    'prepartita verificati'
                  : 'Campione prepartita verificato non ancora disponibile',
              key: const Key('b57-public-learning-count'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (summary.pendingPredictions > 0)
              Text(
                '${summary.pendingPredictions} previsioni future in osservazione',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            const SizedBox(height: 12),
            const Text('Risultati storici dei tre motori',
              style: TextStyle(color: Colors.white70, fontSize: 12,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              key: const Key('b63-home-three-engine-accuracy'),
              children: [
                _rateColumn(name: 'SmartBet',
                  correct: summary.smartBetCorrect,
                  verified: summary.smartBetVerified),
                _rateColumn(name: 'Diego',
                  correct: summary.diegoCorrect,
                  verified: summary.diegoVerified),
                _rateColumn(name: 'Marcatori',
                  correct: summary.scorerScored,
                  verified: summary.scorerVerified),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'SmartBet e Diego: pronostici corretti. Marcatori: '
              'giocatori pronosticati che hanno segnato. '
              'Le tre percentuali non sono direttamente confrontabili.',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le percentuali sui singoli pronostici sono stime, '
              'non risultati garantiti. Le analisi retrospettive non '
              'contano come previsioni certificate.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
