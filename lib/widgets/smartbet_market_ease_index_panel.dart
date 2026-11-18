import 'package:flutter/material.dart';

import '../services/smartbet_market_ease_index_service.dart';

/// Historical MEI is always diagnostic; never a live-pick recommendation.
class SmartBetMarketEaseIndexPanel extends StatelessWidget {
  const SmartBetMarketEaseIndexPanel({
    super.key,
    required this.report,
  });

  final MarketEaseIndexReport report;

  @override
  Widget build(BuildContext context) {
    final scored = report.entries.where((e) => e.score != null).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        key: const Key('b66-mei-panel'),
        initiallyExpanded: false,
        title: const Text(
          'Indice di Facilita Mercato (MEI)',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$scored segmenti valutabili su ${report.entries.length} · SHADOW',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Punteggio storico 0-100 per motore, paese, campionato e '
            'mercato: limite inferiore Wilson 95%, correzione per '
            'sovrastima e Brier relativo. Non e la probabilita di vincita '
            'della prossima partita. Le quote non sono utilizzate.',
          ),
          const SizedBox(height: 6),
          const Text(
            'Serve almeno un campione di 100 pronostici verificati su '
            '14 giornate distinte. Nessuna modifica a pronostici o schedine.',
          ),
          if (report.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nessun dato storico valido: MEI non disponibile.'),
            ),
          ...report.entries.take(12).map((entry) {
            final s = entry.evidence;
            final engine = s.engine.name == 'diego' ? 'Diego AI' : 'SmartBet AI';
            final label = entry.score == null
                ? entry.status == MarketEaseEvidenceStatus.exploratory
                    ? 'In osservazione (campione esplorativo)'
                    : 'N/D: dati insufficienti'
                : '${entry.score!.toStringAsFixed(1)} / 100 · candidato SHADOW';
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.country} · ${s.league} · ${s.market} · $engine',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('MEI storico: $label'),
                  Text(
                    'Risultati: ${s.correct}/${s.sampleSize} · '
                    '${s.distinctMatchDays} giornate · '
                    'Wilson inferiore ${s.wilsonLower95Percent.toStringAsFixed(1)}%',
                  ),
                  Text(
                    'Brier ${s.brierScore?.toStringAsFixed(4) ?? "N/D"} · '
                    'sovrastima ${entry.overconfidencePoints.toStringAsFixed(1)} punti',
                  ),
                  const Divider(),
                ],
              ),
            );
          }),
          if (report.entries.length > 12)
            Text('Mostrati 12 su ${report.entries.length} segmenti.'),
          const Text(
            'SHADOW: un MEI elevato non autorizza correzioni automatiche.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
