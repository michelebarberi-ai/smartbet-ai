import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../services/goalvdline_extra_markets_service.dart';

/// Three extra families, deliberately shadow-only until verified samples
/// and genuine market prices are available. No new API requests or AI calls.
class GoalVdLineExtraMarketsPanel extends StatelessWidget {
  final AnalysisResult? analysis;
  final GoalVdLineVerifiedCountSample? cornersSample;
  final GoalVdLineVerifiedCountSample? shotsSample;

  const GoalVdLineExtraMarketsPanel({
    super.key,
    this.analysis,
    this.cornersSample,
    this.shotsSample,
  });

  @override
  Widget build(BuildContext context) {
    const service = GoalVdLineExtraMarketsService();
    final half = analysis == null
        ? const <GoalVdLineExtraMarketEstimate>[]
        : service.halfTimeScenarios(analysis!);
    final corners = service.countMarketEvidence(
      family: GoalVdLineExtraMarketFamily.totalCorners,
      sample: cornersSample,
    );
    final shots = service.countMarketEvidence(
      family: GoalVdLineExtraMarketFamily.totalShotsOnTarget,
      sample: shotsSample,
    );

    Widget group(String title, List<GoalVdLineExtraMarketEstimate> rows,
        String note, {int maxRows = 6}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 3),
            Text(note, style: const TextStyle(
              color: Colors.white60, fontSize: 10,
            )),
            const SizedBox(height: 7),
            for (final item in rows.take(maxRows))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(
                      item.market,
                      style: const TextStyle(
                        color: Colors.white70, fontSize: 11,
                      ),
                    )),
                    const SizedBox(width: 9),
                    Text(
                      item.probabilityPercent == null
                          ? 'Dati N/D'
                          : '${item.probabilityPercent!.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.probabilityPercent == null
                            ? Colors.orangeAccent
                            : const Color(0xFF9EE3CC),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final halfRows = half.isEmpty
        ? [
            for (final name in [
              ...GoalVdLineExtraMarketsService.firstHalfMarkets,
              ...GoalVdLineExtraMarketsService.secondHalfMarkets,
            ])
              GoalVdLineExtraMarketEstimate(
                market: name,
                probabilityPercent: null,
                experimental: true,
                evidence: 'Analisi sportiva non ancora disponibile',
              ),
          ]
        : half;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('b78-extra-markets-panel'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text(
          'Mercati aggiuntivi · in osservazione',
          style: TextStyle(
            color: Color(0xFF9EE3CC),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'Primo/secondo tempo · Corner · Tiri in porta',
          style: TextStyle(color: Colors.white60, fontSize: 10),
        ),
        children: [
          const Text(
            'Mercati sperimentali: non entrano nella schedina automatica '
            'né nelle statistiche ufficiali finché non sono disponibili '
            'esiti verificati, quote reali e calibrazione.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
          ),
          const SizedBox(height: 7),
          group(
            'Risultato 1° e 2° tempo (1 / X / 2)',
            halfRows,
            'Solo scenario Poisson: ripartizione ipotetica dei gol '
            '45% primo tempo e 55% secondo. Non calibrato.',
          ),
          group(
            'Calci d’angolo · totale partita',
            corners,
            'Over/Under corner: servono 100 partite concluse '
            'e almeno 14 giornate prima di mostrare frequenze storiche.',
            maxRows: 6,
          ),
          group(
            'Tiri in porta · totale partita',
            shots,
            'Non sono i tiri del singolo giocatore: '
            'le offerte Sostituto+ richiedono dati e regole separate.',
            maxRows: 6,
          ),
          const Text(
            'Il bookmaker può offrire anche soglie diverse: '
            'nessuna quota è inventata o dedotta da altri mercati. '
            'Il valore economico si verifica solo alla fine.',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
