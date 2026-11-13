import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_device_learning_preferences.dart';
import '../services/smartbet_learning_overview_service.dart';
import '../services/smartbet_league_market_reliability_service.dart';
import '../services/smartbet_league_market_shadow_service.dart';
import '../services/smartbet_scorer_learning_service.dart';
import '../widgets/smartbet_diagnostic_export_button.dart';
import '../widgets/smartbet_league_market_reliability_panel.dart';
import 'smartbet_learning_monitor_screen.dart';

/// Sola lettura degli archivi esistenti: niente resolver, richieste API
/// o riscritture dello storico quando si apre questa pagina.
class SmartBetLearningOverviewScreen extends StatefulWidget {
  const SmartBetLearningOverviewScreen({super.key});

  @override
  State<SmartBetLearningOverviewScreen> createState() =>
      _SmartBetLearningOverviewScreenState();
}

class _SmartBetLearningOverviewScreenState
    extends State<SmartBetLearningOverviewScreen> {
  SmartBetLearningOverview? _summary;
  SmartBetLeagueMarketReliabilityReport? _leagueMarketReport;
  SmartBetLeagueMarketShadowReport? _shadowMarketReport;
  bool? _enabled;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enabled = await const SmartBetDeviceLearningPreferences()
          .loadEnabled();
      final markets = SmartBetAnalysisHistoryStore.instance;
      await markets.initialize();
      final scorers = SmartBetScorerLearningStore();
      await scorers.initialize();
      final snapshot = SmartBetLearningOverview.fromRecords(
        marketRecords: markets.records,
        scorerRecords: scorers.records,
      );
      // P21W: calculate only from locally persisted history, without
      // network calls, resolving results or altering any prediction.
      final leagueReport = const SmartBetLeagueMarketReliabilityService()
          .evaluate(records: markets.records, asOf: DateTime.now().toUtc());
      final shadowReport = const SmartBetLeagueMarketShadowService()
          .evaluate(records: markets.records, asOf: DateTime.now().toUtc());
      if (!mounted) return;
      setState(() {
        _shadowMarketReport = shadowReport;
        _enabled = enabled;
        _summary = snapshot;
        _leagueMarketReport = leagueReport;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Non riesco a leggere lo storico locale: $e';
      });
    }
  }

  Widget _stat(String name, String value) => ListTile(
    dense: true,
    title: Text(name),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  Widget _panel(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    ),
  );

  String _rate(double? rate) =>
      rate == null ? 'Non disponibile' : '${rate.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intelligenza e apprendimento'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna statistiche locali',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(_error!),
                const SizedBox(height: 12),
                FilledButton(onPressed: _refresh, child: const Text('Riprova')),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _panel('Stato sul dispositivo', [
                  _stat(
                    'Correzioni sperimentali',
                    _enabled == true ? 'Abilitate' : 'Disabilitate',
                  ),
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'Il consenso si modifica solo nelle Impostazioni. '
                      'Anche con l’opzione attiva, una correzione viene '
                      'applicata soltanto se supera i controlli statistici.',
                    ),
                  ),
                ]),
                if (summary != null) ...[
                  _panel('Mercati calcistici — SmartBet AI', [
                    _stat('Previsioni registrate', '${summary.marketRecorded}'),
                    _stat(
                      'Previsioni prospettiche verificate',
                      '${summary.marketVerified}',
                    ),
                    _stat('Corrette', '${summary.marketCorrect}'),
                    _stat('Errate', '${summary.marketWrong}'),
                    _stat('Accuratezza storica', _rate(summary.marketHitRate)),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'La percentuale considera soltanto le previsioni '
                        'registrate prima della partita e successivamente '
                        'risolte. Non misura il rendimento economico.',
                      ),
                    ),
                  ]),
                  _panel('Marcatori AI — storico separato', [
                    _stat('Giocatori registrati', '${summary.scorerRecorded}'),
                    _stat('Previsioni verificate', '${summary.scorerVerified}'),
                    _stat(
                      'Giocatori che hanno segnato',
                      '${summary.scorerScored}',
                    ),
                    _stat('Percentuale storica', _rate(summary.scorerHitRate)),
                    _stat(
                      'Partite distinte verificate',
                      '${summary.scorerVerifiedFixtures}',
                    ),
                    _stat('Giornate distinte', '${summary.scorerVerifiedDays}'),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'La calibrazione dei marcatori richiede almeno '
                        '100 partite e 14 giornate, oltre a una verifica '
                        'positiva su dati separati. Raggiungere queste '
                        'quantità non garantisce l’attivazione.',
                      ),
                    ),
                  ]),
                ],
                if (_leagueMarketReport != null)
                  SmartBetLeagueMarketReliabilityPanel(
                    report: _leagueMarketReport!,
                    shadowReport: _shadowMarketReport,
                  ),
                _panel('Esportazione diagnostica', [
                  const SmartBetDiagnosticExportButton(),
                ]),
                _panel('Correzioni e miglioramenti', [
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'Il numero di correzioni applicate in tempo reale '
                      'alle schedine non è ancora registrato singolarmente. '
                      'Non mostriamo quindi un conteggio inventato. '
                      'Il Learning Monitor confronta invece le previsioni '
                      'storiche originali e calibrate, con Brier Score '
                      'e controlli shadow.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SmartBetLearningMonitorScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Apri Learning Monitor'),
                    ),
                  ),
                ]),
              ],
            ),
    );
  }
}
