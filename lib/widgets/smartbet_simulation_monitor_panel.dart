import 'package:flutter/material.dart';

import '../services/smartbet_simulation_outcome_audit_service.dart';

/// P21E: monitor esclusivamente locale e su richiesta.
/// Non richiama resolver, fetch API, learning gate o correzioni dei pronostici.
class SmartBetSimulationMonitorPanel extends StatefulWidget {
  final Future<SmartBetSimulationOutcomeAuditReport> Function()? loadReport;

  const SmartBetSimulationMonitorPanel({super.key, this.loadReport});

  @override
  State<SmartBetSimulationMonitorPanel> createState() =>
      _SmartBetSimulationMonitorPanelState();
}

class _SmartBetSimulationMonitorPanelState
    extends State<SmartBetSimulationMonitorPanel> {
  bool _running = false;
  String? _error;
  SmartBetSimulationOutcomeAuditReport? _report;

  Future<void> _runLocalAudit() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final report =
          await (widget.loadReport?.call() ??
              SmartBetSimulationOutcomeAuditService().evaluateStored());
      if (!mounted) return;
      setState(() => _report = report);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        key: const ValueKey('p21e_section'),
        initiallyExpanded: false,
        title: const Text(
          'Simulatore • confronto P21E (SHADOW)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Originale vs simulato • dati solo locali'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        children: [
          const Text(
            'Confronta probabilita registrate prima della partita con '
            'risultati gia risolti sul dispositivo. Nessuna nuova analisi, '
            'chiamata API, modifica alle schedine o apprendimento automatico.',
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('p21e_run_audit'),
            onPressed: _running ? null : _runLocalAudit,
            icon: const Icon(Icons.analytics_outlined),
            label: Text(
              _running
                  ? 'Elaborazione locale...'
                  : _report == null
                  ? 'Calcola confronto locale'
                  : 'Aggiorna confronto locale',
            ),
          ),
          if (_running) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Impossibile leggere i dati locali: $_error',
                key: const ValueKey('p21e_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_report != null) ...[
            const SizedBox(height: 12),
            SmartBetSimulationAuditReportView(report: _report!),
          ] else if (!_running)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Nessun confronto ancora eseguito.'),
            ),
        ],
      ),
    );
  }
}

/// Presentazione dei risultati audit P21D senza trasformare Brier in
/// percentuale di pronostici corretti e senza aggregare mercati diversi.
class SmartBetSimulationAuditReportView extends StatelessWidget {
  final SmartBetSimulationOutcomeAuditReport report;

  const SmartBetSimulationAuditReportView({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final metrics = report.metrics.values.toList()
      ..sort((a, b) {
        final bySample = b.sampleSize.compareTo(a.sampleSize);
        if (bySample != 0) return bySample;
        final byEngine = a.engine.compareTo(b.engine);
        return byEngine != 0 ? byEngine : a.market.compareTo(b.market);
      });

    return Column(
      key: const ValueKey('p21e_report'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in report.overall.entries)
          _overallAccuracy(entry.key, entry.value),
        const Text('Confronto scelte prepartita'),
        if (report.choices.isEmpty)
          const Text('In attesa di nuove scelte confrontabili con esito.'),
        for (final e in report.choices.entries)
          Text('${e.key} • ${e.value.settled} confronti: '
              'ufficiale ${e.value.officialHits} corrette, '
              'alternativa ${e.value.alternativeHits} corrette. '
              'Errori corretti ${e.value.fixed}, introdotti ${e.value.introduced}, '
              'saldo ${e.value.fixed - e.value.introduced}.'),
        Text('Snapshot prepartita: ${report.snapshotCount}'),
        Text('Snapshot confrontati: ${report.comparedSnapshots}'),
        Text('Snapshot in attesa di esito: ${report.pendingSnapshots}'),
        Text('Coppie motore-mercato valutate: ${report.comparedMarketPairs}'),
        Text(
          'Esclusi: ${report.conflictingFixtures} risultati contrastanti, '
          '${report.invalidFixtureSnapshots} snapshot non validi, '
          '${report.duplicateSnapshots} duplicati',
        ),
        Text(
          'Mercati non confrontabili: ${report.unmatchedMarketPairs} non '
          'abbinati, ${report.unsupportedMarketPairs} non supportati',
        ),
        const SizedBox(height: 10),
        if (metrics.isEmpty)
          const Text(
            'Non sono ancora disponibili confronti validi: servono '
            'previsioni salvate prima del calcio d’inizio e risultati '
            'finali gia acquisiti nello storico.',
            key: ValueKey('p21e_no_comparisons'),
          ),
        for (final m in metrics) _marketMetric(m),
        const SizedBox(height: 8),
        const Text(
          'Brier inferiore = probabilita piu accurate su quel campione. '
          'Un miglioramento positivo non dimostra superiorita stabile. '
          'Questi valori NON sono la percentuale di pronostici azzeccati; '
          'i mercati e i motori restano separati. I risultati non '
          'attivano correzioni automatiche.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _overallAccuracy(String engine, SmartBetOverallAccuracy summary) {
    if (summary.settled == 0) {
      return Text('$engine • Nessun pronostico concluso');
    }
    String rate(int n) => (100 * n / summary.settled).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$engine • Precisione complessiva', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Ufficiale: ${summary.officialHits}/${summary.settled} • ${rate(summary.officialHits)}%'),
          Text('Scelte confrontate: ${summary.matched.settled}/${summary.settled}'),
          if (summary.matched.settled > 0)
            Text('Simulata sul totale: ${summary.shadowHits}/${summary.settled} • '
                '${rate(summary.shadowHits)}%. Le scelte senza confronto conservano l’esito ufficiale.'),
        ],
      ),
    );
  }

  Widget _marketMetric(SmartBetSimulationOutcomeMarketMetric m) {
    final delta = m.brierImprovement;
    final status = delta > 0
        ? 'Simulato migliore nel campione'
        : delta < 0
        ? 'Originale migliore nel campione'
        : 'Risultati equivalenti nel campione';

    return Card(
      key: ValueKey('p21e_market_${m.engine}_${m.market}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.engine} • ${m.market}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Campioni verificati: ${m.sampleSize} • Esiti positivi: ${m.occurred}',
            ),
            Text(
              'Probabilita media: originale '
              '${(m.meanOriginalProbability * 100).toStringAsFixed(1)}%, '
              'simulata ${(m.meanSimulatedProbability * 100).toStringAsFixed(1)}% '
              '• frequenza osservata '
              '${(m.observedFrequency * 100).toStringAsFixed(1)}%',
            ),
            Text('Brier originale: ${m.originalBrier.toStringAsFixed(4)}'),
            Text('Brier simulato: ${m.simulatedBrier.toStringAsFixed(4)}'),
            Text(
              'Differenza Brier (originale − simulato): '
              '${delta.toStringAsFixed(4)}',
            ),
            Text(
              '$status • '
              '${m.exploratoryOnly ? 'Campione piccolo (<50)' : 'Richiede validazione futura'}',
            ),
          ],
        ),
      ),
    );
  }
}
