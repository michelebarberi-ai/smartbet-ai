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


    Widget group({
      required Key key,
      required String title,
      required List<GoalVdLineExtraMarketEstimate> rows,
      required String note,
    }) {
      return Container(
        margin: const EdgeInsets.only(bottom: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: ExpansionTile(
          key: key,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${rows.length} mercati · in osservazione',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          children: [
            Text(note, style: const TextStyle(
              color: Colors.white60, fontSize: 10,
            )),
            const SizedBox(height: 8),
            for (final item in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.market,
                        style: const TextStyle(
                          color: Colors.white70, fontSize: 11,
                        ),
                      ),
                    ),
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

    final firstHalfRows = halfRows
        .where((item) => item.market.startsWith('1T '))
        .toList(growable: false);
    final secondHalfRows = halfRows
        .where((item) => item.market.startsWith('2T '))
        .toList(growable: false);

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('b78-extra-markets-panel'),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(Icons.more_horiz, color: Color(0xFF00C853)),
          tilePadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Text(
            'Altri',
            style: TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: const Text(
            '1° e 2° tempo · Corner · Tiri in porta',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
          children: [
            const Text(
              'Questi nuovi mercati sono in osservazione. Puoi consultarli, '
              'ma non selezionarli per le schedine fino alla validazione '
              'con risultati verificati, quote reali e calibrazione.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
            ),
            const SizedBox(height: 10),
            group(
              key: const Key('b79-altri-primo-tempo'),
              title: 'Primo tempo · 1 / X / 2',
              rows: firstHalfRows,
              note: 'Scenario Poisson: quota gol del primo tempo ipotizzata '
                  'al 45%. Non calibrato.',
            ),
            group(
              key: const Key('b79-altri-secondo-tempo'),
              title: 'Secondo tempo · 1 / X / 2',
              rows: secondHalfRows,
              note: 'Scenario Poisson: quota gol del secondo tempo ipotizzata '
                  'al 55%. Non calibrato.',
            ),
            group(
              key: const Key('b79-altri-corner'),
              title: 'Corner · totale partita',
              rows: corners,
              note: 'Over/Under corner: servono almeno 100 incontri '
                  'conclusi e 14 giornate con dati verificati.',
            ),
            group(
              key: const Key('b79-altri-tiri-porta'),
              title: 'Tiri in porta · totale partita',
              rows: shots,
              note: 'Solo tiri in porta complessivi, non statistiche '
                  'dei singoli giocatori o scommesse Sostituto+.',
            ),
            const Text(
              'Nessuna quota viene inventata o dedotta da altri mercati. '
              'La disponibilità sul bookmaker va verificata separatamente.',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
