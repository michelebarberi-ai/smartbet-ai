import 'package:flutter/material.dart';

import '../services/smartbet_three_engine_comparison_service.dart';

/// Only historical, matched fixture/market evidence. Never updates live AI.
class SmartBetThreeEngineComparisonPanel extends StatelessWidget {
  const SmartBetThreeEngineComparisonPanel({
    super.key,
    required this.report,
  });

  final SmartBetThreeEngineComparisonReport report;

  String _brier(double? value) => value?.toStringAsFixed(4) ?? 'N/D';

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: ExpansionTile(
      key: const Key('b66-three-engine-comparison'),
      initiallyExpanded: false,
      title: const Text(
        'Confronto storico dei tre motori',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${report.markets.length} mercati confrontabili · SHADOW',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const Text(
          'Solo partite e mercati identici, previsioni registrate '
          'prima del calcio di inizio e risultati reali verificati. '
          'Brier più basso = probabilità storicamente più accurate. '
          'Nessuna correzione automatica delle schedine.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Attenzione: il simulatore può usare gli stessi xG di '
          'SmartBet o Diego. Un accordo non costituisce una conferma '
          'indipendente.',
        ),
        if (report.markets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Non ci sono ancora confronti validi su incontri e mercati '
              'identici. Servono nuove previsioni risolte.',
            ),
          ),
        ...report.markets.take(10).map((market) {
          final s = market;
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.market, style: const TextStyle(
                  fontWeight: FontWeight.bold)),
                Text('Simulatore / SmartBet: ${s.pairedWithSmartBet} partite '
                  '(${s.distinctSmartBetDays} giornate)'),
                Text('Brier simulatore ${_brier(s.simulatorOnSmartBetFixturesBrier)} '
                  '· SmartBet ${_brier(s.smartBetBrier)}'),
                Text(s.smartBetResearchSample
                  ? 'Confronto esplorativo, da validare'
                  : 'Campione SmartBet insufficiente per valutazioni'),
                Text('Simulatore / Diego: ${s.pairedWithDiego} partite '
                  '(${s.distinctDiegoDays} giornate)'),
                Text('Brier simulatore ${_brier(s.simulatorOnDiegoFixturesBrier)} '
                  '· Diego ${_brier(s.diegoBrier)}'),
                Text(s.diegoResearchSample
                  ? 'Confronto esplorativo, da validare'
                  : 'Campione Diego insufficiente per valutazioni'),
                Text('Tripletta completa: ${s.completeTriplets} partite '
                  '· xG condivisi: SmartBet ${s.simulatorSharedSmartBetInputs}, '
                  'Diego ${s.simulatorSharedDiegoInputs}'),
                const Divider(),
              ],
            ),
          );
        }),
        const Text(
          'Non sommare i mercati come se fossero partite indipendenti. '
          'Questa analisi non determina automaticamente il motore migliore.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
