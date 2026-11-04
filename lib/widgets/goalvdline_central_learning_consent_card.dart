import 'package:flutter/material.dart';

import '../services/goalvdline_central_learning_outbox.dart';
import '../services/goalvdline_historical_learning_review.dart';
import '../services/smartbet_analysis_history_store.dart';

/// Consenso esplicito alla raccolta locale P23B1.
/// Nessun dato e inviato ad alcun server in questa fase.
class GoalVdLineCentralLearningConsentCard extends StatefulWidget {
  const GoalVdLineCentralLearningConsentCard({super.key});

  @override
  State<GoalVdLineCentralLearningConsentCard> createState() =>
      _GoalVdLineCentralLearningConsentCardState();
}

class _GoalVdLineCentralLearningConsentCardState
    extends State<GoalVdLineCentralLearningConsentCard> {
  final _outbox = GoalVdLineCentralLearningOutbox.instance;
  final _history = SmartBetAnalysisHistoryStore.instance;
  final _retro = GoalVdLineHistoricalLearningReview.instance;
  bool _loading = true;
  bool _working = false;
  bool _enabled = false;
  int _count = 0;
  int _prepared = 0;
  bool _retroEnabled = false;
  GoalVdLineHistoricalAudit? _audit;
  bool _historicalAvailable = false;

  @override
  void initState() {
    super.initState();
    _history.addListener(_updateHistoryCounts);
    _load();
  }

  @override
  void dispose() {
    _history.removeListener(_updateHistoryCounts);
    super.dispose();
  }

  void _updateHistoryCounts() {
    if (!mounted || !_history.initialized) return;
    setState(() => _audit = _retro.audit(_history.records));
  }

  Future<void> _load() async {
    try {
      await _outbox.initialize();
      await _outbox.eligibleLocalDrafts();
      await _history.initialize();
      await _retro.initialize();
      if (!mounted) return;
      setState(() {
        _enabled = _outbox.consentGranted;
        _count = _outbox.pendingCount;
        _audit = _retro.audit(_history.records);
        _prepared = _retro.preparedCount;
        _retroEnabled = _retro.consentGranted;
        _historicalAvailable = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _changeConsent(bool next) async {
    if (_working || _loading) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          next ? 'Contribuire al cervello AI?' : 'Revocare il consenso?',
        ),
        content: Text(
          next
              ? 'Saranno conservati sul dispositivo soltanto i nuovi '
                    'pronostici originali, con partita, mercato, probabilita e '
                    'orario. Nessun dato viene inviato al server in questa '
                    'versione. Lo storico precedente richiede una autorizzazione '
                    'separata qui sotto.'
              : 'La raccolta si fermera e le bozze locali ancora '
                    'in attesa saranno cancellate. Le analisi personali '
                    'resteranno inalterate. La copia storica eventualmente '
                    'preparata si gestisce separatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(next ? 'Acconsento' : 'Revoca e cancella'),
          ),
        ],
      ),
    );
    if (!mounted || allowed != true) return;
    setState(() => _working = true);
    try {
      await _outbox.setConsent(next);
      if (!mounted) return;
      setState(() {
        _enabled = _outbox.consentGranted;
        _count = _outbox.pendingCount;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aggiornare il consenso.')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _prepareHistory() async {
    if (_working || _loading || !_historicalAvailable) return;
    final audit = _audit;
    if (audit == null || audit.preparable == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Preparare lo storico precedente?'),
        content: Text(
          'Verranno create soltanto sul dispositivo copie minime delle '
          'previsioni storiche recuperabili (${audit.preparable} al momento). '
          '${audit.settledCandidates} hanno un esito locale, '
          '${audit.awaitingResult} sono ancora da verificare. '
          'Il numero indica previsioni, non partite distinte. '
          'Il materiale resta separato dalla coda dei nuovi pronostici. '
          'Nessun invio al server. Lo storico personale non viene modificato. '
          'Per trasmettere dati storici in futuro sara richiesto un altro consenso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Prepara solo sul telefono'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _working = true);
    try {
      await _retro.prepareFromHistory(_history.records);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile preparare lo storico locale.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteHistoryCopy() async {
    if (_working || _loading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare la copia retrospettiva?'),
        content: const Text(
          'Saranno eliminate soltanto le copie preparate per il cervello AI. '
          'Tutte le tue analisi nello Storico resteranno intatte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Elimina copia'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _working = true);
    try {
      await _retro.deletePrepared();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile eliminare la copia locale.')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF263445),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Contributo al cervello AI',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'P23B: raccolta solo locale, nessun invio',
                style: TextStyle(color: Colors.white70),
              ),
              value: _enabled,
              onChanged: (_loading || _working) ? null : _changeConsent,
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Consenso attivo · $_count nuove previsioni in coda. '
                        'La trasmissione e disattivata.'
                  : 'Nuove previsioni: raccolta disattivata. '
                        'Coda live separata dallo storico.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Divider(color: Colors.white24, height: 24),
            const Text(
              'Storico precedente · P23B3',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 7),
            if (!_historicalAvailable)
              const Text(
                'Impossibile leggere il conteggio dello storico su questo dispositivo.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              )
            else ...[
              Text(
                'Archivio: ${_audit?.total ?? 0} previsioni · '
                '${_audit?.uniqueFixtures ?? 0} partite distinte',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Con esito locale: ${_audit?.settledCandidates ?? 0} · '
                'Da verificare: ${_audit?.awaitingResult ?? 0}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Non idonee: ${_audit?.excluded ?? 0} · '
                'Partite future: ${_audit?.futureFixtures ?? 0}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 5),
              Text(
                'Copie retrospettive preparate: $_prepared '
                '${_retroEnabled ? '(autorizzazione locale attiva)' : '(nessuna autorizzazione)'}',
                style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Le copie sono locali e non sono previsioni certificate dal server. '
                'Non modificano il cervello AI e non saranno inviate senza nuovo consenso.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        (_loading || _working || (_audit?.preparable ?? 0) == 0)
                        ? null
                        : _prepareHistory,
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: Text(
                      _retroEnabled
                          ? 'Aggiorna copia storica'
                          : 'Prepara storico locale',
                    ),
                  ),
                  if (_retroEnabled)
                    TextButton.icon(
                      onPressed: (_loading || _working)
                          ? null
                          : _deleteHistoryCopy,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Elimina copia'),
                    ),
                  TextButton.icon(
                    onPressed: (_loading || _working) ? null : _load,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Aggiorna conteggi'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
