import 'package:flutter/material.dart';

import '../widgets/smartbet_simulation_monitor_panel.dart';
import '../widgets/smartbet_simulation_learning_panel.dart';
import '../widgets/smartbet_league_market_reliability_panel.dart';

import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_market_intelligence_audit_service.dart';
import '../services/smartbet_paired_calibration_service.dart';
import '../services/smartbet_cross_market_audit_service.dart';
import '../services/smartbet_analysis_comparison_store.dart';
import '../services/smartbet_walk_forward_backtest_service.dart';
import '../services/smartbet_shadow_learning_store.dart';
import '../services/smartbet_shadow_outcome_service.dart';
import '../services/smartbet_learning_gate_service.dart';
import '../services/smartbet_league_market_reliability_service.dart';

class SmartBetLearningMonitorScreen extends StatefulWidget {
  const SmartBetLearningMonitorScreen({super.key});

  @override
  State<SmartBetLearningMonitorScreen> createState() =>
      _SmartBetLearningMonitorScreenState();
}

class _SmartBetLearningMonitorScreenState
    extends State<SmartBetLearningMonitorScreen> {
  final _store = SmartBetAnalysisHistoryStore.instance;

  List<SmartBetAnalysisRecord> _records = [];
  SmartBetWalkForwardReport? _report;
  SmartBetShadowOutcomeReport? _shadowReport;
  SmartBetLearningGateReport? _gateReport;
  bool _runningShadow = false;
  bool _loading = true;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
      _shadowReport = null;
      _gateReport = null;
    });

    try {
      await _store.initialize();
      await SmartBetAnalysisComparisonStore.instance.initialize();
      if (!mounted) return;
      setState(() {
        _records = _store.records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _runShadowComparison() async {
    if (_runningShadow) return;

    setState(() {
      _runningShadow = true;
      _error = null;
    });

    try {
      await _store.initialize();

      final shadow = SmartBetShadowLearningStore.instance;
      await shadow.initialize();

      final history = _store.records;

      final report = const SmartBetShadowOutcomeService().evaluate(
        history: history,
        predictions: shadow.predictions,
      );

      if (!mounted) return;

      final gateReport = const SmartBetLearningGateService().evaluate(
        report,
        asOf: DateTime.now().toUtc(),
      );

      setState(() {
        _records = history;
        _shadowReport = report;
        _gateReport = gateReport;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _runningShadow = false);
      }
    }
  }

  Future<void> _runBacktest() async {
    setState(() => _running = true);

    // Consente alla schermata di mostrare il caricamento.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      final report = const SmartBetWalkForwardBacktestService().evaluate(
        _records,
      );

      if (!mounted) return;
      setState(() => _report = report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Widget _marketIntelligenceSection() {
    final report = const MarketIntelligenceAuditService().evaluate(_records);
    final groups = report.groups.toList()
      ..sort((a, b) => b.samples.compareTo(a.samples));

    String pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Market Intelligence Auditor • SHADOW',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Analisi diagnostica delle probabilità originali. '
          'Solo previsioni precedenti alla partita e risolte; '
          'Diego AI soltanto se qualificato. '
          'Nessuna modifica a pronostici o schedine.',
        ),
        const SizedBox(height: 12),
        Text(
          'Campioni validi: ${report.includedRecords}  •  '
          'Esclusi: ${report.excludedRecords}',
        ),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Non ci sono ancora risultati storici '
              'sufficientemente verificati da visualizzare.',
            ),
          ),
        ...groups.take(12).map((m) {
          final isDiego = m.engine == SmartBetAnalysisEngine.diego;
          final sufficient = m.samples >= 30;

          final gap = m.marketGap == null
              ? 'N/D'
              : '${(m.marketGap! * 100).toStringAsFixed(1)} pp';

          final roi = m.hypotheticalUnitRoi == null
              ? 'N/D'
              : pct(m.hypotheticalUnitRoi!);

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isDiego ? "Diego AI" : "SmartBet"} • ${m.market}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${m.samples} previsioni • '
                    '${m.correct} corrette • '
                    '${sufficient ? "Campione da approfondire" : "Campione piccolo"}',
                  ),
                  Text(
                    'Probabilità media: ${pct(m.meanProbability)} • '
                    'Frequenza reale: ${pct(m.observedFrequency)}',
                  ),
                  Text('Brier Score: ${m.brierScore.toStringAsFixed(4)}'),
                  Text(
                    'Quote disponibili: ${m.quotedSamples} • '
                    'Scostamento implicito: $gap',
                  ),
                  Text('ROI teorico su quote registrate: $roi'),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        const Text(
          'La probabilità implicita è grezza, non depurata '
          'dal margine bookmaker. Il ROI è simulato e '
          'non rappresenta guadagni effettivi. '
          'Campioni piccoli non dimostrano affidabilità.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _crossMarketSection() {
    final report = const SmartBetCrossMarketAuditService().evaluate(
      records: _records,
      links: SmartBetAnalysisComparisonStore.instance.links,
    );

    String pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confronto tra mercati differenti • SHADOW',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'SmartBet e Diego AI sulla stessa partita '
          'con mercati differenti. Solo coppie storiche '
          'valide. Nessuna modifica alle schedine.',
        ),
        const SizedBox(height: 12),
        Text(
          'Coppie valide: ${report.totalPairs} • '
          'Partite distinte: ${report.distinctFixtures}',
        ),
        Text(
          'Coppie escluse: ${report.excludedLinks} • '
          'Gruppi: ${report.groups.length}',
        ),
        const SizedBox(height: 10),
        if (report.groups.isEmpty)
          const Text(
            'Nessuna coppia valida con mercati differenti '
            'ancora disponibile.',
          ),
        ...report.groups
            .take(12)
            .map(
              (m) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SmartBet: ${m.smartBetMarket}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Diego AI: ${m.diegoMarket}'),
                      const SizedBox(height: 8),
                      Text(
                        '${m.pairs} coppie • '
                        '${m.distinctDays} giorni distinti',
                      ),
                      Text(
                        'Accuratezza SmartBet: '
                        '${pct(m.smartBetAccuracy)}',
                      ),
                      Text(
                        'Accuratezza Diego: '
                        '${pct(m.diegoAccuracy)}',
                      ),
                      Text(
                        'Brier SmartBet: '
                        '${m.smartBetBrier.toStringAsFixed(4)}',
                      ),
                      Text(
                        'Brier Diego: '
                        '${m.diegoBrier.toStringAsFixed(4)}',
                      ),
                      const SizedBox(height: 8),
                      Text('Entrambi corretti: ${m.bothCorrect}'),
                      Text(
                        'Solo SmartBet corretto: '
                        '${m.smartBetOnlyCorrect}',
                      ),
                      Text(
                        'Solo Diego corretto: '
                        '${m.diegoOnlyCorrect}',
                      ),
                      Text('Entrambi errati: ${m.bothWrong}'),
                      const SizedBox(height: 8),
                      Text(
                        m.enoughForExploratoryReview
                            ? 'Campione da approfondire'
                            : 'Campione ancora limitato',
                      ),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 8),
        const Text(
          'Mercati differenti rappresentano eventi '
          'differenti. I risultati non dimostrano '
          'automaticamente la superiorità di un motore.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _pairedCalibrationSection() {
    final report = const SmartBetPairedCalibrationService().evaluate(_records);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confronto omogeneo SmartBet / Diego AI',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Stessa partita, stesso mercato e risultati '
          'verificati. Solo previsioni registrate prima '
          'del calcio d’inizio. Modalità shadow.',
        ),
        const SizedBox(height: 12),
        Text(
          'Coppie valide: ${report.totalPairs} • '
          'Mercati: ${report.markets.length}',
        ),
        if (report.markets.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Nessuna coppia confrontabile disponibile.'),
          ),
        ...report.markets.take(12).map((m) {
          final delta = m.smartBetBrierAdvantage;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.market,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${m.pairedFixtures} coppie • '
                    '${m.distinctDays} giorni distinti',
                  ),
                  Text(
                    'Brier SmartBet: '
                    '${m.smartBetBrier.toStringAsFixed(4)}',
                  ),
                  Text(
                    'Brier Diego: '
                    '${m.diegoBrier.toStringAsFixed(4)}',
                  ),
                  Text(
                    'Differenza Diego − SmartBet: '
                    '${delta.toStringAsFixed(4)}',
                  ),
                  Text(
                    m.enoughForExploratoryReview
                        ? 'Campione da approfondire'
                        : 'Campione ancora limitato',
                  ),
                ],
              ),
            ),
          );
        }),
        const Text(
          'Un Brier inferiore è migliore sul campione '
          'osservato. La soglia esplorativa non dimostra '
          'superiorità statistica.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  String _number(double? value) =>
      value == null ? 'N/D' : value.toStringAsFixed(4);

  @override
  Widget build(BuildContext context) {
    final completed = _records
        .where(
          (r) =>
              r.prospectiveEligible &&
              (r.status == SmartBetAnalysisStatus.correct ||
                  r.status == SmartBetAnalysisStatus.wrong),
        )
        .toList();

    final correct = completed
        .where((r) => r.status == SmartBetAnalysisStatus.correct)
        .length;

    final accuracy = completed.isEmpty
        ? null
        : correct / completed.length * 100;

    final resolved = completed.where((r) => r.resolvedAt != null).length;

    final markets = <String, List<int>>{};

    for (final r in completed) {
      final key = '${r.engine.name} | ${normalizeAnalysisMarket(r.market)}';
      final values = markets.putIfAbsent(key, () => [0, 0]);
      values[0]++;
      if (r.status == SmartBetAnalysisStatus.correct) {
        values[1]++;
      }
    }

    final rankedMarkets = markets.entries.toList()
      ..sort((a, b) => b.value[0].compareTo(a.value[0]));

    Widget metric(String title, String value) => Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartBet Learning Monitor'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna dati locali',
            onPressed: _running ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Diagnostica locale - modalità sperimentale',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                metric('Analisi registrate', '${_records.length}'),
                metric('Previsioni concluse', '${completed.length}'),
                metric('Previsioni corrette', '$correct'),
                metric(
                  'Accuratezza storica',
                  accuracy == null ? 'N/D' : '${accuracy.toStringAsFixed(1)}%',
                ),
                metric('Esiti con resolvedAt', '$resolved'),
                const SizedBox(height: 12),
                SmartBetLeagueMarketReliabilityPanel(
                  report: const SmartBetLeagueMarketReliabilityService()
                      .evaluate(records: _records, asOf: DateTime.now().toUtc()),
                ),

                const SizedBox(height: 18),
                const Text(
                  'Prestazioni per mercato',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                if (rankedMarkets.isEmpty)
                  const Text('Nessun risultato disponibile.'),

                ...rankedMarkets.take(15).map((entry) {
                  final total = entry.value[0];
                  final wins = entry.value[1];
                  final rate = wins / total * 100;

                  return ListTile(
                    title: Text(entry.key),
                    subtitle: Text('$wins corretti su $total'),
                    trailing: Text('${rate.toStringAsFixed(1)}%'),
                  );
                }),

                const Divider(height: 32),
                const Text(
                  'Backtest cronologico P11',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Confronta le probabilità originali e calibrate '
                  'utilizzando soltanto risultati storicamente '
                  'disponibili. Non modifica le schedine.',
                ),
                const SizedBox(height: 12),

                FilledButton(
                  onPressed: _running ? null : _runBacktest,
                  child: Text(_running ? 'Elaborazione...' : 'Esegui backtest'),
                ),

                if (_running) const LinearProgressIndicator(),

                if (_report != null) ...[
                  const SizedBox(height: 12),
                  metric('Pronostici valutati', '${_report!.evaluatedRecords}'),
                  metric(
                    'Pronostici ricalibrati',
                    '${_report!.adjustedRecords}',
                  ),
                  metric(
                    'Brier originale - totale',
                    _number(_report!.originalBrier),
                  ),
                  metric(
                    'Brier calibrato - totale',
                    _number(_report!.calibratedBrier),
                  ),
                  metric(
                    'Brier originale - ricalibrati',
                    _number(_report!.originalBrierAdjusted),
                  ),
                  metric(
                    'Brier calibrato - ricalibrati',
                    _number(_report!.calibratedBrierAdjusted),
                  ),
                  metric(
                    'Miglioramento Brier',
                    _number(_report!.brierImprovement),
                  ),
                  const Text(
                    'Miglioramento positivo = errore Brier minore. '
                    'I valori non dimostrano da soli un vantaggio '
                    'statisticamente significativo.',
                  ),
                ],

                const SmartBetSimulationMonitorPanel(),
                const SmartBetSimulationLearningPanel(),
                const Divider(height: 32),
                const Divider(height: 32),
                _marketIntelligenceSection(),
                const Divider(height: 32),
                _pairedCalibrationSection(),
                const Divider(height: 32),
                _crossMarketSection(),
                const Divider(height: 32),
                const Text(
                  'Apprendimento reale P13',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Confronta le previsioni originali con quelle '
                  'adattive salvate prima delle partite. '
                  'Utilizza soltanto risultati verificati.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _runningShadow ? null : _runShadowComparison,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    _runningShadow
                        ? 'Verifica in corso...'
                        : 'Confronta risultati reali',
                  ),
                ),
                if (_shadowReport != null) ...[
                  const SizedBox(height: 12),
                  metric(
                    'Previsioni verificate',
                    '${_shadowReport!.overall.evaluated}',
                  ),
                  metric(
                    'Previsioni ricalibrate',
                    '${_shadowReport!.overall.adjusted}',
                  ),
                  metric(
                    'Correzioni migliorative',
                    '${_shadowReport!.overall.improved}',
                  ),
                  metric(
                    'Correzioni peggiorative',
                    '${_shadowReport!.overall.worsened}',
                  ),
                  metric(
                    'Brier originale',
                    _number(_shadowReport!.overall.originalBrier),
                  ),
                  metric(
                    'Brier adattivo',
                    _number(_shadowReport!.overall.calibratedBrier),
                  ),
                  metric(
                    'Miglioramento totale',
                    _number(_shadowReport!.overall.improvement),
                  ),
                  metric(
                    'Miglioramento sui ricalibrati',
                    _number(_shadowReport!.overall.adjustedImprovement),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Un miglioramento positivo indica un '
                    'Brier Score inferiore. Servono molti '
                    'risultati indipendenti per giudicare '
                    'affidabile una correzione.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Confronto per motore',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ..._shadowReport!.byEngine.entries.map(
                    (entry) => metric(
                      entry.key,
                      '${entry.value.evaluated} analisi | '
                      'Brier ${_number(entry.value.originalBrier)}'
                      ' → ${_number(entry.value.calibratedBrier)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confronto per mercato',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ..._shadowReport!.byMarket.entries
                      .take(15)
                      .map(
                        (entry) => metric(
                          entry.key,
                          '${entry.value.evaluated} analisi | '
                          'Δ ${_number(entry.value.improvement)}',
                        ),
                      ),
                ],

                if (_gateReport != null) ...[
                  const Divider(height: 32),
                  const Text(
                    'Learning Gate P14',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Valuta se le correzioni storiche '
                    'sono abbastanza stabili per una '
                    'sperimentazione controllata. '
                    'Non modifica le schedine.',
                  ),
                  const SizedBox(height: 12),

                  metric(
                    'Mercati candidati al trial',
                    '\${_gateReport!.eligibleMarkets}',
                  ),

                  if (_gateReport!.decisions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Nessuna correzione con risultati '
                        'sufficienti per essere valutata.',
                      ),
                    ),

                  ..._gateReport!.decisions.take(20).map((decision) {
                    final status = switch (decision.status) {
                      SmartBetLearningGateStatus.insufficientData =>
                        'Dati insufficienti',
                      SmartBetLearningGateStatus.inconsistentImprovement =>
                        'Miglioramento non stabile',
                      SmartBetLearningGateStatus.eligibleForTrial =>
                        'Candidato al trial - non attivo',
                    };

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\${decision.engine} | '
                              '\${decision.market}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(status),
                            const SizedBox(height: 6),
                            Text(
                              '\${decision.adjustedSamples} '
                              'previsioni ricalibrate | '
                              '\${decision.distinctDays} giorni',
                            ),
                            Text(
                              'Miglioramento Brier: '
                              '\${_number(decision.overallImprovement)}',
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      'Errore: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
    );
  }
}
