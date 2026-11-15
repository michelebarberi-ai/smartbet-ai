import 'package:flutter/material.dart';

import '../services/goalvdline_central_learning_mobile_sync.dart';
import '../services/goalvdline_central_learning_outbox.dart';
import '../services/goalvdline_mobile_token_vault.dart';

/// User-facing consent controls. This must remain accessible in public builds
/// even when all technical monitoring/export/admin tools are hidden.
///
/// There is no automatic upload yet. Switching consent on permits only
/// local collection of newly generated, prospective analysis drafts.
class GoalVdLinePublicParticipationCard extends StatefulWidget {
  const GoalVdLinePublicParticipationCard({super.key});

  @override
  State<GoalVdLinePublicParticipationCard> createState() =>
      _GoalVdLinePublicParticipationCardState();
}

class _GoalVdLinePublicParticipationCardState
    extends State<GoalVdLinePublicParticipationCard> {
  final _store = GoalVdLineCentralLearningOutbox.instance;
  final _vault = GoalVdLineMobileTokenVault();
  final _sync = GoalVdLineCentralLearningMobileSync();
  bool _loading = true;
  bool _working = false;
  bool _enabled = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _store.initialize();
      if (!mounted) return;
      setState(() {
        _enabled = _store.consentGranted;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Preferenze privacy non disponibili.';
        });
      }
    }
  }

  Future<void> _changeConsent(bool next) async {
    if (_loading || _working) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(next ? 'Contribuire al miglioramento AI?' : 'Revocare il consenso?'),
        content: Text(next
            ? 'Verranno conservate sul dispositivo soltanto nuove '
              'previsioni generate prima delle partite. Nessun invio '
              'automatico al server. Il consenso può essere revocato.'
            : 'Saranno eliminate le nuove previsioni ancora nella coda '
              'locale. Per i dati eventualmente già inviati è disponibile '
              'la cancellazione separata qui sotto.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(next ? 'Acconsento' : 'Revoca'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() { _working = true; _message = null; });
    try {
      await _store.setConsent(next);
      if (!mounted) return;
      setState(() {
        _enabled = _store.consentGranted;
        _message = next
            ? 'Raccolta locale autorizzata; nessun invio automatico.'
            : 'Consenso revocato: coda locale eliminata.';
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Impossibile salvare la preferenza.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _eraseRemote() async {
    if (_working || _loading) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare i dati già inviati?'),
        content: const Text(
          'Questa operazione elimina dal server i dati associati '
          'alla credenziale del dispositivo, se ancora disponibile. '
          'Non cancella lo storico locale delle tue analisi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confermo cancellazione'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() { _working = true; _message = null; });
    try {
      final token = await _vault.read();
      if (token == null || !GoalVdLineMobileTokenVault.validToken(token)) {
        if (mounted) {
          setState(() => _message =
            'Credenziale non presente nel Portachiavi: '
            'cancellazione remota non eseguita.');
        }
        return;
      }
      final result = await _sync.eraseRemote(
        baseUrl: GoalVdLineCentralLearningMobileSync.defaultServerUrl,
        token: token,
      );
      if (!mounted) return;
      if (result.success) {
        await _store.setConsent(false);
        await _vault.delete();
      }
      setState(() {
        _enabled = _store.consentGranted;
        _message = result.message;
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Cancellazione non confermata.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('b57-public-privacy-card'),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Contribuisci al miglioramento AI'),
            subtitle: const Text(
              'Solo nuove previsioni locali. Nessun invio '
              'automatico; consenso revocabile in qualsiasi momento.',
            ),
            value: _enabled,
            onChanged: (_loading || _working) ? null : _changeConsent,
          ),
          if (_loading || _working) const LinearProgressIndicator(),
          TextButton.icon(
            onPressed: (_loading || _working) ? null : _eraseRemote,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Cancella eventuali dati già inviati'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(_message!, key: const Key('b57-privacy-status')),
            ),
        ],
      ),
    );
  }
}
