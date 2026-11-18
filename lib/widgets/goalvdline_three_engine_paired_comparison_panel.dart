import 'package:flutter/material.dart';

import '../services/goalvdline_three_engine_paired_comparison_service.dart';
import '../services/smartbet_analysis_history_store.dart';

/// Diagnostica sui medesimi incontri/mercati. Nessuna promozione live.
class GoalVdLineThreeEnginePairedComparisonPanel extends StatelessWidget {
  final GoalVdLinePairedThreeEngineReport report;
  final bool fixedBenchmark;
  final int frozenFixtures;

  const GoalVdLineThreeEnginePairedComparisonPanel({
    super.key,
    required this.report,
    this.fixedBenchmark = false,
    this.frozenFixtures = 0,
  });

  static String _engine(SmartBetAnalysisEngine e) => switch (e) {
    SmartBetAnalysisEngine.smartBet => 'SmartBet',
    SmartBetAnalysisEngine.diego => 'Diego AI',
    SmartBetAnalysisEngine.thirdBrain => 'Terzo cervello',
  };

  @override
  Widget build(BuildContext context) {
    final segments = report.segments;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        key: Key(fixedBenchmark
            ? 'three-engine-fixed-benchmark-panel'
            : 'three-engine-paired-panel'),
        initiallyExpanded: false,
        title: Text(
          fixedBenchmark
              ? 'Mercati fissi dei tre motori · SHADOW'
              : 'Confronto reale dei tre motori · SHADOW',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          fixedBenchmark
              ? '$frozenFixtures partite congelate · '
                  '${report.pairedFixtureMarkets} confronti risolti'
              : '${report.pairedFixtureMarkets} partite-mercato confrontabili · '
                  '${report.researchReadySegments} segmenti con campione sufficiente',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (fixedBenchmark)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Benchmark separato: i mercati vengono scelti prima '
                'della partita e le probabilita\u0027 sono congelate alla '
                'prima analisi disponibile. Gli esiti sono letti dallo '
                'storico locale solo dopo la verifica del risultato. '
                'Nessun invio a Neon, modifica quote, MEI o pronostici.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const Text(
            'Stessa partita, stesso mercato e risultato reale. '
            'Probabilità registrate prima del calcio d’inizio: '
            'confrontiamo Brier, Log Loss e calibrazione. '
            'L’accuratezza è identica per tutti quando il mercato coincide. '
            'Valori Brier e Log Loss più bassi sono preferibili.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '${report.eligibleRecords} previsioni valide; '
            '${report.eligibleFixtureMarkets} coppie partita-mercato nello storico; '
            '${report.pairedFixtureMarkets} presenti per tutti e tre; '
            '${report.conflictingFixtureMarkets} gruppi ambigui esclusi. '
            'Finestra: ultimi 12 mesi.',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (segments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nessuna terna verificata sulla stessa partita e mercato. '
                'Non confrontiamo mercati differenti o percentuali '
                'ricostruite dopo il risultato.',
                key: Key('three-engine-no-paired-data'),
              ),
            ),
          for (final segment in segments.take(10))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${segment.country} · ${segment.league} · '
                    '${segment.market}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${segment.fixtureCount} incontri · '
                    '${segment.distinctMatchDays} giornate · '
                    '${segment.sufficientEvidence ? "Campione esplorativo sufficiente" : "Campione insufficiente"}',
                    style: TextStyle(
                      color: segment.sufficientEvidence
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    'Terzo cervello: ${segment.thirdInputSource} · '
                    '${segment.thirdModelVersion}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  for (final metric in segment.metrics)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '${_engine(metric.engine)}: '
                        'Brier ${metric.brierScore.toStringAsFixed(3)} · '
                        'Log Loss ${metric.logLoss.toStringAsFixed(3)} · '
                        'Gap ${metric.calibrationGapPoints.toStringAsFixed(1)} pt · '
                        'successi ${metric.correct}/${metric.sampleSize}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const Divider(),
                ],
              ),
            ),
          if (segments.length > 10)
            Text(
              'Mostrati 10 segmenti su ${segments.length}.',
              style: const TextStyle(fontSize: 11),
            ),
          Text(
            fixedBenchmark
              ? 'Questo benchmark non include le selezioni storiche '
                'ricostruite, ma soltanto probabilita\u0027 disponibili '
                'prima del kickoff. Se manca anche un solo motore, il '
                'mercato non entra nel confronto. Il terzo modello '
                'puo\u0027 condividere le fonti statistiche. '
                'La quarta AI resta non attiva.'
              : 'Le previsioni sono quelle selezionate e registrate nello '
                'storico: la copertura comune può essere bassa. '
                'Il terzo modello può condividere la fonte dei dati sportivi. '
                'Nessuna classifica abilita una quarta AI o modifica le schedine. '
                'Anche con 100 incontri e 14 giornate serve validazione '
                'prospettica indipendente prima di considerare un miglioramento.',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
