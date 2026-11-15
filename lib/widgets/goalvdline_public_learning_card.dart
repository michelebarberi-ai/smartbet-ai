import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';

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

  const GoalVdLinePublicLearningSummary({
    required this.verifiedPredictions,
    required this.distinctFixtures,
    required this.pendingPredictions,
    required this.verifiedMatchDays,
    required this.smartBetVerified,
    required this.diegoVerified,
  });

  static GoalVdLinePublicLearningSummary fromRecords(
    Iterable<SmartBetAnalysisRecord> records, {
    DateTime? asOf,
  }) {
    final now = (asOf ?? DateTime.now()).toUtc();
    final unique = <String>{};
    final fixtureIds = <int>{};
    final matchDays = <String>{};
    var resolved = 0;
    var pending = 0;
    var smartBet = 0;
    var diego = 0;

    for (final r in records) {
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
      if (r.engine == SmartBetAnalysisEngine.smartBet) smartBet++;
      if (r.engine == SmartBetAnalysisEngine.diego) diego++;
    }
    return GoalVdLinePublicLearningSummary(
      verifiedPredictions: resolved,
      distinctFixtures: fixtureIds.length,
      pendingPredictions: pending,
      verifiedMatchDays: matchDays.length,
      smartBetVerified: smartBet,
      diegoVerified: diego,
    );
  }
}

/// Users need reassurance that model performance is checked, not raw audit
/// dashboards, export buttons, token entry or unvalidated percentages.
class GoalVdLinePublicLearningCard extends StatelessWidget {
  const GoalVdLinePublicLearningCard({
    super.key,
    required this.records,
    this.asOf,
  });

  final List<SmartBetAnalysisRecord> records;
  /// Injectable cutoff for deterministic tests, defaults to current time.
  final DateTime? asOf;

  @override
  Widget build(BuildContext context) {
    final summary = GoalVdLinePublicLearningSummary.fromRecords(
      records, asOf: asOf,
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
