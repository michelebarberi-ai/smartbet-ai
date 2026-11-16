import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_league_market_reliability_service.dart';

/// Local, read-only league/market ranking based on prospective settled
/// predictions. Does not change picks, odds, model weights or backend state.
/// A lower Wilson 95% bound ranks conservatively, but is NOT a guarantee.
class SmartBetLeagueReliabilityRankingPanel extends StatefulWidget {
  const SmartBetLeagueReliabilityRankingPanel({
    super.key,
    required this.report,
  });

  final SmartBetLeagueMarketReliabilityReport report;

  @override
  State<SmartBetLeagueReliabilityRankingPanel> createState() =>
      _SmartBetLeagueReliabilityRankingPanelState();
}

class _SmartBetLeagueReliabilityRankingPanelState
    extends State<SmartBetLeagueReliabilityRankingPanel> {
  String? _selectedMarket;
  bool _showAll = false;

  static bool _hasEnoughEvidence(SmartBetLeagueMarketReliability segment) =>
      segment.engine == SmartBetAnalysisEngine.smartBet &&
      segment.sampleSize >=
          SmartBetLeagueMarketReliabilityService.minimumExploratoryFixtures &&
      segment.distinctMatchDays >=
          SmartBetLeagueMarketReliabilityService.minimumDistinctMatchDays;

  static String _evidenceLabel(SmartBetLeagueMarketEvidenceLevel level) =>
      switch (level) {
        SmartBetLeagueMarketEvidenceLevel.strongShadowCandidate =>
          'Candidato SHADOW, non attivo',
        SmartBetLeagueMarketEvidenceLevel.signal =>
          'Segnale da validare',
        SmartBetLeagueMarketEvidenceLevel.exploratory =>
          'Campione esplorativo',
        SmartBetLeagueMarketEvidenceLevel.insufficient =>
          'Dati insufficienti',
      };

  @override
  Widget build(BuildContext context) {
    final qualified = widget.report.segments
        .where(_hasEnoughEvidence)
        .toList(growable: false);
    final markets = qualified.map((entry) => entry.market).toSet().toList()
      ..sort();
    final selected = markets.contains(_selectedMarket)
        ? _selectedMarket
        : null;
    final ranked = qualified
        .where((entry) => selected == null || entry.market == selected)
        .toList()
      ..sort((a, b) {
        // A conservative lower bound avoids ranking a very small but lucky
        // sample above a better-supported segment merely on its hit rate.
        final conservative =
            b.wilsonLower95Percent.compareTo(a.wilsonLower95Percent);
        if (conservative != 0) return conservative;
        final count = b.sampleSize.compareTo(a.sampleSize);
        if (count != 0) return count;
        final league = a.league.compareTo(b.league);
        if (league != 0) return league;
        return a.market.compareTo(b.market);
      });
    final display = _showAll ? ranked : ranked.take(15).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        key: const Key('b62-league-ranking'),
        initiallyExpanded: false,
        title: const Text(
          'Classifica campionati più affidabili',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        subtitle: Text(
          '${qualified.length} campionato/mercato con campione minimo',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Solo risultati reali registrati prima delle partite su '
            'questo iPhone. Ordine prudente: limite inferiore '
            'dell’intervallo al 95%, non soltanto successi percentuali. '
            'È una graduatoria storica, non una previsione garantita '
            'né una regola che modifica automaticamente la schedina.',
          ),
          const SizedBox(height: 10),
          if (markets.isNotEmpty)
            Row(
              children: [
                const Text('Mercato: '),
                Expanded(
                  child: DropdownButton<String>(
                    key: const Key('b62-league-market-filter'),
                    isExpanded: true,
                    value: selected ?? 'ALL',
                    items: [
                      const DropdownMenuItem<String>(
                        value: 'ALL',
                        child: Text('Tutti i mercati'),
                      ),
                      ...markets.map(
                        (market) => DropdownMenuItem<String>(
                          value: market,
                          child: Text(market),
                        ),
                      ),
                    ],
                    onChanged: (next) => setState(() {
                      _selectedMarket = next == 'ALL' ? null : next;
                      _showAll = false;
                    }),
                  ),
                ),
              ],
            ),
          if (ranked.isEmpty)
            const Padding(
              key: Key('b62-league-ranking-no-evidence'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nessuna classifica attendibile con i dati disponibili. '
                'Servono almeno 50 pronostici verificati e 14 giornate '
                'per lo stesso campionato e mercato.',
              ),
            ),
          for (var i = 0; i < display.length; i++) ...[
            ListTile(
              key: Key('b62-league-ranking-row-$i'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${i + 1}. ${display[i].country} · ${display[i].league}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${display[i].market} · '
                '${display[i].correct}/${display[i].sampleSize} corretti · '
                '${display[i].distinctMatchDays} giornate\n'
                'Limite prudenziale 95%: '
                '${display[i].wilsonLower95Percent.toStringAsFixed(1)}% · '
                '${_evidenceLabel(display[i].evidenceLevel)}',
              ),
              trailing: Text(
                '${display[i].observedAccuracyPercent.toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              isThreeLine: true,
            ),
            const Divider(height: 6),
          ],
          if (!_showAll && ranked.length > 15)
            TextButton(
              key: const Key('b62-league-ranking-show-all'),
              onPressed: () => setState(() => _showAll = true),
              child: Text('Mostra tutti i ${ranked.length} gruppi'),
            ),
          if (_showAll && ranked.length > 15)
            TextButton(
              onPressed: () => setState(() => _showAll = false),
              child: const Text('Mostra solo i primi 15'),
            ),
          const SizedBox(height: 8),
          Text(
            'Esclusi dalla classifica: '
            '${widget.report.segments.where((item) =>
              item.engine == SmartBetAnalysisEngine.smartBet &&
              !_hasEnoughEvidence(item)).length} gruppi con '
            'dati insufficienti. I dettagli completi, compresi '
            'Diego AI e i controlli SHADOW, sono nel pannello seguente.',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
