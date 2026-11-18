import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../services/dual_engine_analysis_service.dart';
import '../services/goalvdline_third_brain_service.dart';
import '../services/smartbet_analysis_history_store.dart';

/// Scheda diagnostica, chiusa inizialmente, riutilizzata in Schedina
/// e Combinazioni. Il terzo motore si calcola solo all'apertura.
class GoalVdLineThreeBrainsExpansion extends StatefulWidget {
  final int fixtureId;
  final AnalysisResult smartBet;
  final DualEngineAnalysis? dual;
  final String selectedMarket;
  final int? selectedProbability;

  const GoalVdLineThreeBrainsExpansion({
    super.key,
    required this.fixtureId,
    required this.smartBet,
    required this.dual,
    required this.selectedMarket,
    this.selectedProbability,
  });

  @override
  State<GoalVdLineThreeBrainsExpansion> createState() =>
      _GoalVdLineThreeBrainsExpansionState();
}

class _GoalVdLineThreeBrainsExpansionState
    extends State<GoalVdLineThreeBrainsExpansion> {
  bool _expanded = false;

  String _pct(double value) =>
      '${(value * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

  String _market(String value) => switch (value) {
        'HOME SCORES' => 'Casa segna',
        'AWAY SCORES' => 'Ospite segna',
        _ => value,
      };

  static const _ordinaryMarkets = <String>{
    'OVER 0.5', 'UNDER 5.5', 'UNDER 4.5', 'UNDER 3.5',
    'OVER 1.5', 'OVER 2.5', 'UNDER 2.5',
    'HOME SCORES', 'AWAY SCORES', '1X', 'X2', '12',
    '1', 'X', '2', 'GOAL', 'NO GOAL',
    'MULTIGOL 1-3', 'MULTIGOL 1-4', 'MULTIGOL 2-4',
  };

  Widget _readout(String title, String market, String detail) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 86,
              child: Text(title, style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w600,
                fontSize: 11))),
            Expanded(child: Text(market,
              style: const TextStyle(color: Colors.white, fontSize: 11))),
            const SizedBox(width: 6),
            Text(detail, style: const TextStyle(
              color: Colors.greenAccent, fontWeight: FontWeight.w600,
              fontSize: 11)),
          ],
        ),
      );

  Widget _buildContents() {
    final smart = widget.smartBet;
    final dual = widget.dual;
    final diego = dual?.diego;
    final smartValid = smart.smartScore > 0;
    final smartProbability = widget.selectedProbability;

    // Non trattenere o usare quote: il ranking è esclusivamente sportivo.
    final simulation = const GoalVdLineThirdBrainService().evaluate(
      smartBet: smart, diego: diego,
    );
    final diegoMarket = dual?.comparison.diegoMarket ?? 'N/D';
    final diegoProbability = dual?.comparison.diegoProbability;
    final metaRecords = SmartBetAnalysisHistoryStore.instance
        .recordsForFixture(widget.fixtureId)
        .where((record) =>
            record.engine == SmartBetAnalysisEngine.metaAi &&
            record.prospectiveEligible &&
            record.probability != null)
        .toList()
      ..sort((a, b) => b.probability!.compareTo(a.probability!));
    final selectedMetaMarket = normalizeAnalysisMarket(widget.selectedMarket);
    SmartBetAnalysisRecord? selectedMeta;
    for (final entry in metaRecords) {
      if (entry.market == selectedMetaMarket) {
        selectedMeta = entry;
        break;
      }
    }

    final choices = simulation?.markets
        .where((item) => _ordinaryMarkets.contains(item.market))
        .take(8).toList() ?? const <GoalVdLineThirdBrainMarket>[];
    final orChoices = simulation?.markets
        .where((item) => item.market.contains(' O '))
        .take(3).toList() ?? const <GoalVdLineThirdBrainMarket>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _readout(
            'SmartBet AI',
            smartValid ? _market(widget.selectedMarket) : 'Non disponibile',
            smartValid && smartProbability != null
                ? '${smartProbability}%' : 'N/D',
          ),
          _readout(
            'Diego AI',
            diego == null ? 'Non disponibile'
                : (diegoMarket == 'N/D'
                    ? 'Analisi statistica disponibile'
                    : _market(diegoMarket)),
            diegoProbability == null ? 'N/D' : _pct(diegoProbability),
          ),
          _readout(
            'Simulatore',
            simulation == null
                ? 'Dati sui gol attesi insufficienti'
                : 'Poisson bivariata',
            simulation == null ? 'N/D' : 'Attivo',
          ),
          const SizedBox(height: 5),
          _readout(
            '4° Meta AI',
            metaRecords.isEmpty
                ? 'Non valutabile: servono SmartBet e Diego sullo stesso mercato'
                : selectedMeta == null
                    ? 'Sintesi SHADOW registrata su ${metaRecords.length} mercati'
                    : 'Sintesi ${_market(selectedMeta.market)} (SHADOW)',
            selectedMeta == null
                ? (metaRecords.isEmpty ? 'N/D' : '${metaRecords.length} mercati')
                : _pct(selectedMeta.probability!),
          ),
          if (metaRecords.isNotEmpty) ...[
            Text(
              'Quarto cervello: somma ponderata delle probabilità '
              'sportive dei motori, con pesi MEI soltanto se '
              'esiste uno storico sufficiente. '
              'Il simulatore condivide gli xG di un motore: '
              'non è una terza conferma indipendente.',
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
            const Text(
              'Le stime sono in osservazione SHADOW: non sono '
              'consigli di giocata e non modificano le schedine.',
              style: TextStyle(color: Colors.amberAccent, fontSize: 10),
            ),
          ],
          if (simulation != null) ...[
            const SizedBox(height: 9),
            Text(
              'Gol attesi: ${simulation.homeExpectedGoals.toStringAsFixed(2)} – '
              '${simulation.awayExpectedGoals.toStringAsFixed(2)} '
              '· dati: ${simulation.inputSource}'
              '${simulation.dataConfidence != null
                ? ' · qualità ${simulation.dataConfidence}/100'
                : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
            if (simulation.sharesDiegoInputs)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text(
                  'Il simulatore utilizza gli xG di Diego: metodo diverso, '
                  'ma non una seconda conferma indipendente dei dati.',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 10),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              '1X2: 1 ${_pct(simulation.forMarket('1')!.probability)}'
              ' · X ${_pct(simulation.forMarket('X')!.probability)}'
              ' · 2 ${_pct(simulation.forMarket('2')!.probability)}',
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
            Text(
              'Over 2.5 ${_pct(simulation.forMarket('OVER 2.5')!.probability)}'
              ' · Goal ${_pct(simulation.forMarket('GOAL')!.probability)}',
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
            const SizedBox(height: 12),
            const Text('MERCATI ORDINATI PER PROBABILITÀ SPORTIVA',
              style: TextStyle(color: Colors.white70,
                fontWeight: FontWeight.bold, fontSize: 10)),
            const SizedBox(height: 7),
            ...choices.map((item) => Padding(
              key: Key('b63-sim-market-${widget.fixtureId}-${item.market}'),
              padding: const EdgeInsets.only(bottom: 7),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: Text(_market(item.market),
                      style: const TextStyle(color: Colors.white, fontSize: 11))),
                    Text(_pct(item.probability),
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                  const SizedBox(height: 3),
                  ClipRRect(borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: item.probability.clamp(0.0, 1.0).toDouble(),
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFF43A56D),
                    )),
                ],
              ),
            )),
            if (orChoices.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('MERCATI OPPURE (UNIONE DEGLI EVENTI)',
                style: TextStyle(color: Colors.white60,
                  fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              ...orChoices.map((item) => _readout(
                '', _market(item.market), _pct(item.probability))),
            ],
            const SizedBox(height: 7),
            Text('Risultati più probabili: ${simulation.likelyScores.map(
              (x) => '${x.label} (${_pct(x.probability)})').join(' · ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
            const SizedBox(height: 8),
            const Text(
              'Sensibilità: gol attesi variati di ±15%. '
              'Le percentuali sono teoriche e non calibrate. '
              'Non si tratta di intervalli di confidenza.',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
            if (choices.isNotEmpty)
              Text('Prima stima: ${_market(choices.first.market)} '
                '(${_pct(choices.first.probability)}; '
                'scenari ${_pct(choices.first.lowerScenario)}–'
                '${_pct(choices.first.upperScenario)}).',
                style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Non inventiamo una simulazione quando mancano xG validi. '
                'Il sistema conserva soltanto le analisi effettivamente disponibili.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 10.5),
              ),
            ),
          const SizedBox(height: 9),
          const Text(
            'Le quote non entrano nei tre calcoli: servono solo alla fine '
            'per verificare mercati disponibili e soglia >1,20. '
            'Questa scheda non sostituisce la selezione ufficiale e '
            'non modifica il cervello centrale.',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    key: Key('b63-three-brains-${widget.fixtureId}'),
    color: const Color(0xFF111827),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Colors.white12),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: Key('b63-three-brains-tile-${widget.fixtureId}'),
      initiallyExpanded: false,
      onExpansionChanged: (value) => setState(() => _expanded = value),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: EdgeInsets.zero,
      title: const Text('Analisi motori AI',
        style: TextStyle(color: Colors.white,
          fontWeight: FontWeight.bold, fontSize: 12)),
      subtitle: const Text('Previsioni, simulazione e mercati più probabili',
        style: TextStyle(color: Colors.white54, fontSize: 10)),
      children: _expanded ? [_buildContents()] : const [],
    ),
  );
}
