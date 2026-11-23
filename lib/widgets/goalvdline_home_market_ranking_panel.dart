import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_market_ease_index_service.dart';

/// Ranked by a conservative historical MEI, not by bookmaker price.
/// Requires 100 settled prospective predictions over 14 match days
/// for the *same engine, country, league and market*.
class GoalVdLineHomeMarketRankingPanel extends StatelessWidget {
  final List<SmartBetAnalysisRecord> records;
  final DateTime? asOf;

  const GoalVdLineHomeMarketRankingPanel({
    super.key,
    required this.records,
    this.asOf,
  });

  String _engine(SmartBetAnalysisEngine engine) => switch (engine) {
    SmartBetAnalysisEngine.smartBet => 'SmartBet',
    SmartBetAnalysisEngine.diego => 'Diego AI',
    SmartBetAnalysisEngine.simulator => 'Simulatore',
    SmartBetAnalysisEngine.metaAi => 'Meta AI',
  };

  Widget _entry(MarketEaseIndexEntry item) {
    final evidence = item.evidence;
    final score = item.score;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${evidence.market} · ${_engine(evidence.engine)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              if (score != null)
                Text(
                  'MEI ${score.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Color(0xFF69F0AE),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          Text(
            '${evidence.country} · ${evidence.league}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Text(
            '${evidence.correct}/${evidence.sampleSize} corretti · '
            '${evidence.distinctMatchDays} giornate · '
            'Limite Wilson ${evidence.wilsonLower95Percent.toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = const SmartBetMarketEaseIndexService().evaluate(
      records: records,
      asOf: (asOf ?? DateTime.now()).toUtc(),
    );
    final ranked = report.entries.where((entry) =>
        entry.score != null &&
        (entry.evidence.engine == SmartBetAnalysisEngine.smartBet ||
         entry.evidence.engine == SmartBetAnalysisEngine.diego)).toList();
    final watching = report.entries.where((entry) =>
        entry.score == null &&
        entry.evidence.sampleSize >= 10 &&
        (entry.evidence.engine == SmartBetAnalysisEngine.smartBet ||
         entry.evidence.engine == SmartBetAnalysisEngine.diego)).toList();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('b78-home-market-ranking'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        title: const Text(
          'Mercati storicamente più affidabili',
          style: TextStyle(color: Colors.white,
            fontSize: 13, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Per motore, campionato e mercato · senza quote',
          style: TextStyle(color: Colors.white60, fontSize: 10),
        ),
        children: [
          if (ranked.isEmpty)
            const Text(
              'Nessun mercato con dati sufficienti: servono almeno '
              '100 esiti verificati e 14 giornate sullo stesso '
              'motore, campionato e mercato.',
              key: Key('b78-home-no-market-leader'),
              style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
            )
          else ...[
            const Text(
              'Classifica MEI: limite inferiore Wilson, penalità '
              'di sovrastima e qualità della calibrazione.',
              style: TextStyle(color: Colors.white60, fontSize: 10),
            ),
            const SizedBox(height: 8),
            for (final entry in ranked.take(5)) _entry(entry),
          ],
          if (ranked.isEmpty && watching.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${watching.length} gruppi ancora in osservazione. '
              'Nessuna percentuale può essere considerata consolidata.',
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Il mercato migliore nello storico non è automaticamente '
            'il pronostico migliore per la prossima partita. '
            'Le quote vengono valutate solo dopo.',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
