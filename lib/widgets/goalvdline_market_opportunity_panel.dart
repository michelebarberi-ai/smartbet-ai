import 'package:flutter/material.dart';

import '../services/goalvdline_market_opportunity_service.dart';

/// Read-only market comparison in an existing analyzed match card.
/// It does NOT choose, alter, or automatically add any market to a coupon.
class GoalVdLineMarketOpportunityPanel extends StatelessWidget {
  final GoalVdLineMarketOpportunityReport report;

  const GoalVdLineMarketOpportunityPanel({
    super.key,
    required this.report,
  });

  Widget _market(GoalVdLineMarketOpportunity entry, int index) {
    final odd = entry.actualOdd;
    final implied = entry.impliedProbabilityPercent;
    final evidence = entry.evidence;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${index + 1}. ${entry.market}',
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '${entry.modelProbabilityPercent.toStringAsFixed(1)}% AI',
                style: const TextStyle(
                  color: Color(0xFF69F0AE), fontSize: 12,
                ),
              ),
            ],
          ),
          Text(
            odd == null
                ? 'Quota reale non disponibile'
                : 'Quota ${odd.toStringAsFixed(2)} · '
                  'pareggio matematico ${implied!.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white70, fontSize: 11,
            ),
          ),
          Text(
            evidence == null
                ? 'Storico per questo mercato: nessun campione'
                : entry.evidenceIsQualified
                    ? 'Storico: ${evidence.correct}/${evidence.sampleSize} · '
                      'Wilson inferiore ${evidence.wilsonLower95Percent.toStringAsFixed(1)}%'
                    : 'Storico in osservazione: ${evidence.sampleSize} esiti, '
                      '${evidence.distinctMatchDays} giornate',
            style: const TextStyle(
              color: Colors.white54, fontSize: 10,
            ),
          ),
          Text(
            entry.assessment,
            style: const TextStyle(
              color: Colors.orangeAccent, fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = report.rankedSportingMarkets;
    final top = options.take(3).toList();
    final selected = report.selected;
    if (selected != null &&
        !top.any((e) => e.market.trim().toUpperCase() ==
            selected.market.trim().toUpperCase())) {
      top.add(selected);
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('b78-market-opportunity-panel'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        title: const Text(
          'Mercati più probabili · controllo quote',
          style: TextStyle(
            color: Color(0xFF95D5B2),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          selected == null
              ? 'Analisi sportiva prima, quota e storico dopo'
              : selected.assessment,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected == null
                ? Colors.white60 : Colors.orangeAccent,
            fontSize: 10,
          ),
        ),
        children: [
          const Text(
            'Probabilità stimate dal modello, non successi garantiti. '
            'La classifica non usa quote. Il controllo del valore è '
            'soltanto informativo e non modifica la schedina.',
            style: TextStyle(color: Colors.white60, fontSize: 10),
          ),
          const SizedBox(height: 9),
          if (top.isEmpty)
            const Text(
              'Nessun mercato sportivo con stima disponibile.',
              style: TextStyle(color: Colors.white70),
            ),
          for (var i = 0; i < top.length; i++) _market(top[i], i),
          if (selected != null && !report.selectedMarketIsTopSporting)
            const Text(
              'Il mercato della schedina non è il primo nella classifica '
              'puramente sportiva. La quota non modifica il primo pronostico.',
              style: TextStyle(color: Colors.amberAccent, fontSize: 10),
            ),
          const Text(
            'Non riempire una multipla con selezioni dalla quota bassa '
            'soltanto per aumentare la quota totale. Senza conferma '
            'storica e quota reale, il valore resta non dimostrato.',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
