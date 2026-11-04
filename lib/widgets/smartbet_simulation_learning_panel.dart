import 'package:flutter/material.dart';

import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_simulation_learning_validation_service.dart';
import '../services/smartbet_simulation_shadow_store.dart';
import '../services/smartbet_simulation_shadow_policy_service.dart';
import '../services/smartbet_simulation_shadow_projection_service.dart';

/// P21H: lettura locale su richiesta. Non applica pesi alle previsioni.
class SmartBetSimulationLearningPanel extends StatefulWidget {
  final Future<SmartBetSimulationLearningReport> Function()? loadReport;

  const SmartBetSimulationLearningPanel({super.key, this.loadReport});

  @override
  State<SmartBetSimulationLearningPanel> createState() =>
      _SmartBetSimulationLearningPanelState();
}

class _SmartBetSimulationLearningPanelState
    extends State<SmartBetSimulationLearningPanel> {
  bool _running = false;
  String? _error;
  SmartBetSimulationLearningReport? _report;
  bool _policyBusy = false;
  String? _policyMessage;
  List<SmartBetSimulationShadowPolicy> _activePolicies = const [];
  List<SmartBetSimulationShadowProjection> _forwardPreview = const [];

  Future<void> _reloadPolicyPreview() async {
    final policies = await SmartBetSimulationShadowPolicyService()
        .readPolicies();
    await SmartBetSimulationShadowStore.instance.initialize();
    final preview = const SmartBetSimulationShadowProjectionService().preview(
      snapshots: SmartBetSimulationShadowStore.instance.snapshots,
      policies: policies,
      asOf: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _activePolicies = policies;
      _forwardPreview = preview;
    });
  }

  Future<void> _promoteShadow() async {
    if (_policyBusy || _running || _report == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attivare esperimenti SHADOW?'),
        content: const Text(
          'Le correzioni saranno salvate solo nel monitor sperimentale. '
          'Non cambieranno schedine, quote o pronostici ufficiali. '
          'Saranno approvate soltanto con i campioni e i controlli richiesti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Conferma SHADOW'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() {
      _policyBusy = true;
      _policyMessage = null;
    });
    try {
      final outcome = await SmartBetSimulationShadowPolicyService().refresh(
        report: _report!,
        optedIn: true,
        asOf: DateTime.now(),
      );
      await _reloadPolicyPreview();
      if (!mounted) return;
      setState(
        () => _policyMessage =
            'Policy SHADOW: ${outcome.promoted} approvate, '
            '${outcome.rolledBack} ritirate, ${outcome.rejected} respinte.',
      );
    } catch (error) {
      if (mounted)
        setState(() => _policyMessage = 'Policy non disponibili: $error');
    } finally {
      if (mounted) setState(() => _policyBusy = false);
    }
  }

  Future<void> _disablePolicies() async {
    if (_policyBusy || _running) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ritirare tutte le policy SHADOW?'),
        content: const Text(
          'Questa operazione cancella soltanto i pesi sperimentali locali. '
          'Non modifica storico, snapshot o schedine ufficiali.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ritira policy'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() {
      _policyBusy = true;
      _policyMessage = null;
    });
    try {
      await SmartBetSimulationShadowPolicyService().disableAll();
      await _reloadPolicyPreview();
      if (mounted)
        setState(
          () => _policyMessage = 'Tutte le policy SHADOW sono state ritirate.',
        );
    } catch (error) {
      if (mounted)
        setState(() => _policyMessage = 'Rollback non riuscito: $error');
    } finally {
      if (mounted) setState(() => _policyBusy = false);
    }
  }

  Future<void> _runLocalValidation() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final report =
          await (widget.loadReport?.call() ??
              SmartBetSimulationLearningValidationService(
                shadowStore: SmartBetSimulationShadowStore.instance,
                historyStore: SmartBetAnalysisHistoryStore.instance,
              ).evaluateStored());
      if (!mounted) return;
      setState(() => _report = report);
      // Nei test con report iniettato non leggere gli archivi locali.
      // Nel flusso reale le policy SHADOW restano attive.
      if (widget.loadReport == null) {
        try {
          await _reloadPolicyPreview();
        } catch (error) {
          if (mounted) {
            setState(
              () => _policyMessage = 'Lettura policy non disponibile: $error',
            );
          }
        }
      }
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
        key: const ValueKey('p21h_section'),
        initiallyExpanded: false,
        title: const Text(
          'Apprendimento simulatore • P21H (SHADOW)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Validazione cronologica • nessuna correzione live',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        children: [
          const Text(
            'Verifica se pesi sperimentali fra previsione originale e '
            'simulata riducono gli errori su partite successive. '
            'Usa soltanto dati gia salvati sul dispositivo: niente '
            'nuove analisi, API, cambi di quota o modifiche alle schedine.',
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('p21h_run_validation'),
            onPressed: _running ? null : _runLocalValidation,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              _running
                  ? 'Validazione locale in corso...'
                  : _report == null
                  ? 'Valida correzioni locali'
                  : 'Aggiorna validazione locale',
            ),
          ),
          if (_running) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Validazione locale non disponibile: $_error',
                key: const ValueKey('p21h_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_report != null) ...[
            const SizedBox(height: 12),
            SmartBetSimulationLearningReportView(report: _report!),
            const SizedBox(height: 10),
            const Divider(),
            const Text(
              'Policy sperimentali P21L • approvazione manuale, '
              'solo SHADOW. Nessun effetto sui pronostici ufficiali.',
              key: ValueKey('p21v_policy_heading'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('p21v_promote_shadow'),
                  onPressed: (_running || _policyBusy) ? null : _promoteShadow,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Valuta e approva policy SHADOW'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('p21v_disable_shadow'),
                  onPressed: (_running || _policyBusy)
                      ? null
                      : _disablePolicies,
                  icon: const Icon(Icons.undo),
                  label: const Text('Ritira tutte le policy'),
                ),
              ],
            ),
            if (_policyBusy) const LinearProgressIndicator(),
            if (_policyMessage != null)
              Text(_policyMessage!, key: const ValueKey('p21v_policy_message')),
            Text('Policy sperimentali attuali: ${_activePolicies.length}'),
            if (_forwardPreview.isNotEmpty) ...[
              const Text(
                'Proiezioni SHADOW su partite ancora da iniziare '
                '(policy promossa prima dello snapshot):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final p in _forwardPreview)
                Text(
                  '#${p.fixtureId} ${p.engine} • ${p.market}: '
                  '${(p.projected * 100).toStringAsFixed(1)}% SHADOW '
                  '(originale ${(p.original * 100).toStringAsFixed(1)}%)',
                ),
            ] else
              const Text(
                'Nessuna proiezione futura valida per le policy attuali. '
                'Servono nuovi snapshot prepartita acquisiti DOPO la promozione.',
              ),
          ] else if (!_running)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Nessuna validazione ancora eseguita.'),
            ),
        ],
      ),
    );
  }
}

/// I candidati P21G sono solo proposte di prova, mai approvazioni automatiche.
class SmartBetSimulationLearningReportView extends StatelessWidget {
  final SmartBetSimulationLearningReport report;

  const SmartBetSimulationLearningReportView({super.key, required this.report});

  static String _decimal(double? value, {int digits = 4}) =>
      value == null ? 'n.d.' : value.toStringAsFixed(digits);

  static String _decision(SmartBetSimulationLearningDecision decision) {
    switch (decision) {
      case SmartBetSimulationLearningDecision.insufficientData:
        return 'Campione insufficiente';
      case SmartBetSimulationLearningDecision.noTrainingAdvantage:
        return 'Nessun vantaggio nel training';
      case SmartBetSimulationLearningDecision.validationFailed:
        return 'Correzione respinta nella validazione';
      case SmartBetSimulationLearningDecision.trialCandidate:
        return 'Candidato a ulteriori prove (NON attivo)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final markets = report.markets.toList()
      ..sort((a, b) {
        final bySample = b.eligibleCases.compareTo(a.eligibleCases);
        if (bySample != 0) return bySample;
        final byEngine = a.engine.compareTo(b.engine);
        if (byEngine != 0) return byEngine;
        return a.market.compareTo(b.market);
      });
    return Column(
      key: const ValueKey('p21h_report'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Snapshot totali: ${report.totalSnapshots}'),
        Text('Snapshot senza risultato: ${report.pendingSnapshots}'),
        Text('Mercati valutati: ${markets.length}'),
        Text('Candidati per ulteriori test: ${report.trialCandidates}'),
        Text(
          'Esclusi: ${report.conflictingSnapshots} risultati contrastanti, '
          '${report.invalidSnapshots} non validi, '
          '${report.duplicateSnapshots} duplicati',
        ),
        Text(
          'Mercati non confrontabili: ${report.unmatchedPairs} mancanti, '
          '${report.unsupportedPairs} non supportati',
        ),
        const SizedBox(height: 10),
        if (markets.isEmpty)
          const Text(
            'Non sono ancora disponibili mercati valutabili. '
            'Servono snapshot prepartita ed esiti finali locali.',
            key: ValueKey('p21h_empty'),
          ),
        for (final item in markets) _marketCard(item),
        const SizedBox(height: 8),
        const Text(
          'Brier inferiore significa una probabilita mediamente piu '
          'accurata nel campione, non una maggiore percentuale di schedine '
          'vincenti. Anche un candidato validato resta sperimentale. '
          'Questo pannello NON modifica le previsioni.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _marketCard(SmartBetSimulationLearningMarketResult item) {
    final weight = item.candidateSimulationWeight == null
        ? 'n.d.'
        : '${(item.candidateSimulationWeight! * 100).toStringAsFixed(0)}%';
    return Card(
      key: ValueKey('p21h_market_${item.engine}_${item.market}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.engine} • ${item.market} • ${item.modelVersion}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(_decision(item.decision)),
            Text(
              'Campioni: ${item.eligibleCases} • '
              'training ${item.trainingCases} (${item.trainingDays} giorni) • '
              'validazione ${item.validationCases} (${item.validationDays} giorni)',
            ),
            Text('Dati di qualita bassa: ${item.lowQualityCases}'),
            Text('Peso sperimentale del simulatore: $weight'),
            Text(
              'Brier training originale: ${_decimal(item.trainingOriginalBrier)} '
              '• candidato: ${_decimal(item.trainingCandidateBrier)}',
            ),
            Text(
              'Brier validazione originale: ${_decimal(item.validationOriginalBrier)} '
              '• candidato: ${_decimal(item.validationCandidateBrier)}',
            ),
            Text(
              'Miglioramento Brier validazione: '
              '${_decimal(item.validationImprovement)}',
            ),
            Text(
              'Prima meta validazione: '
              '${_decimal(item.firstValidationHalfImprovement)} '
              '• seconda meta: '
              '${_decimal(item.secondValidationHalfImprovement)}',
            ),
          ],
        ),
      ),
    );
  }
}
