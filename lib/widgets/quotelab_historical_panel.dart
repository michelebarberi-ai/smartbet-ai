import 'package:flutter/material.dart';

import '../services/quotelab_historical_service.dart';

/// Third evaluation lens. No bookmaker odds enter SmartBet or Diego here.
class QuoteLabHistoricalPanel extends StatelessWidget {
  const QuoteLabHistoricalPanel({super.key, required this.report});

  final QuoteLabHistoricalReport report;

  String _level(QuoteLabEvidenceLevel level) => switch (level) {
    QuoteLabEvidenceLevel.insufficient => 'Dati insufficienti',
    QuoteLabEvidenceLevel.exploratory => 'Indicazione esplorativa',
    QuoteLabEvidenceLevel.needsValidation =>
      'Campione da verificare su partite successive',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        key: const Key('b56-quotelab-panel'),
        initiallyExpanded: false,
        title: const Text('QuoteLab · Quote storiche vs risultati',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${report.usableQuotedOutcomes} pronostici quotati e risolti · '
          '${report.segments.length} gruppi',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Terza lettura INDIPENDENTE: non modifica SmartBet, Diego '
            'o le schedine. Esamina soltanto quote realmente salvate '
            'prima della partita e risultati conclusi. '
            'Non rappresenta tutte le quote offerte dai bookmaker.',
          ),
          const SizedBox(height: 7),
          const Text(
            'Probabilità implicita lorda = 1 / quota; contiene il margine '
            'del bookmaker, quindi non è una probabilità reale calibrata. '
            'Una fascia quotata non indica una partita sicura.',
          ),
          const SizedBox(height: 7),
          Text(
            'Esclusi: ${report.excludedRecords} · '
            'Duplicati: ${report.duplicates} · '
            'Conflitti: ${report.conflicts}',
          ),
          const SizedBox(height: 8),
          if (report.segments.isEmpty)
            const Text(
              'Nessun dato storico sufficiente per confrontare quote '
              'e risultati: non mostriamo percentuali inventate.',
              key: Key('b56-quotelab-empty'),
            ),
          ...report.segments.take(12).map((segment) {
            final scope = segment.isAllLeagues
                ? 'Tutti i campionati'
                : '${segment.country} • ${segment.league}';
            final hit = segment.hitRatePercent.toStringAsFixed(1);
            final gross = segment.averageGrossImpliedPercent.toStringAsFixed(1);
            final low = segment.wilsonLower95Percent.toStringAsFixed(1);
            final high = segment.wilsonUpper95Percent.toStringAsFixed(1);
            final roi = segment.historicalRoiPercent.toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$scope · ${segment.market} · quota ${segment.priceBand.label}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Esiti corretti: ${segment.successes}/${segment.observations}'
                      ' ($hit%) · ${segment.matchDays} giornate'),
                  Text('Probabilità da quota (lorda): $gross% · '
                    'Intervallo successi 95%: $low%–$high%'),
                  Text('ROI retrospettivo per 1 unità: $roi% '
                      '(campione selezionato, NON una strategia)'),
                  Text(_level(segment.evidenceLevel),
                    style: const TextStyle(fontSize: 12)),
                  const Divider(),
                ],
              ),
            );
          }),
          if (report.segments.length > 12)
            Text('Mostrati 12 di ${report.segments.length} gruppi.'),
          const Text(
            'Per stimare la vera affidabilità delle quote di mercato '
            'servono uno storico completo, bookmaker e timestamp, '
            'con verifica cronologica su partite mai usate per stimare '
            'il modello.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
