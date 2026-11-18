import 'package:flutter/material.dart';

import '../services/smartbet_market_ease_index_service.dart';

/// Read-only diagnostic: cannot change a prediction, coupon or calibration.
class SmartBetMarketEaseIndexPanel extends StatelessWidget {
  const SmartBetMarketEaseIndexPanel({super.key, required this.report});

  final SmartBetMarketEaseIndexReport report;

  @override
  Widget build(BuildContext context) {
    final entries = report.segments;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        key: const Key('market-ease-index-shadow-panel'),
        initiallyExpanded: false,
        title: const Text(
          'Indice affidabilità storica · sperimentale',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${report.measurableSegments} segmenti valutabili / '
          '${entries.length} osservati · ultimi 12 mesi',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Analisi SHADOW indipendente per motore, campionato e mercato. '
            'Base: limite inferiore Wilson 95%, con malus di sovrastima '
            'e Brier peggiore del riferimento. Non usa le quote e '
            'non cambia pronostici, schedine o calibrazione.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Servono almeno 100 incontri per segmento, 14 giornate '
            'distinte e una probabilità registrata prima di ogni partita. '
            'Il punteggio NON è la probabilità di riuscita della prossima partita.',
            style: TextStyle(fontSize: 12),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nessuno storico prospettico risolto disponibile '
                'negli ultimi 12 mesi.',
              ),
            ),
          ...entries.take(12).map((entry) {
            final s = entry.evidence;
            final engine = switch (s.engine.name) {
              'diego' => 'Diego AI',
              'thirdBrain' => 'Terzo cervello · Poisson',
              _ => 'SmartBet AI',
            };
            final score = entry.score;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.country} · ${s.league} · ${s.market} · $engine',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    score == null
                        ? 'Indice: N/D (campione insufficiente)'
                        : 'Indice: ${score.toStringAsFixed(1)}/100 · solo SHADOW',
                    key: score == null
                        ? const Key('market-ease-insufficient')
                        : const Key('market-ease-score'),
                    style: TextStyle(
                      color: score == null
                          ? Colors.orangeAccent
                          : Colors.greenAccent,
                    ),
                  ),
                  Text(
                    'Risultati: ${s.correct}/${s.sampleSize} · '
                    '${s.distinctMatchDays} giornate · '
                    'Wilson 95%: '
                    '${s.wilsonLower95Percent.toStringAsFixed(1)}'
                    '–${s.wilsonUpper95Percent.toStringAsFixed(1)}%',
                  ),
                  if (s.inputSource != null)
                    Text('Origine xG: ${s.inputSource}; '
                      'modello: ${s.modelVersion ?? "N/D"}. '
                      'Non indipendente nei dati di ingresso.',
                      style: const TextStyle(fontSize: 11)),
                  Text(
                    'Brier: ${s.brierScore?.toStringAsFixed(4) ?? "N/D"} · '
                    'scostamento: '
                    '${s.calibrationGapPoints?.toStringAsFixed(1) ?? "N/D"} punti',
                  ),
                  if (score == null)
                    Text(
                      entry.status,
                      style: const TextStyle(fontSize: 11),
                    ),
                  const Divider(),
                ],
              ),
            );
          }),
          if (entries.length > 12)
            Text(
              'Mostrati 12 segmenti su ${entries.length}. '
              'Quelli valutabili sono ordinati per indice; '
              'gli altri restano senza punteggio.',
            ),
          const Text(
            'Il confronto prospettico con il modello precedente è '
            'necessario prima di qualsiasi utilizzo nelle selezioni.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
