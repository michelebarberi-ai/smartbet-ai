import 'package:flutter/material.dart';

import '../services/goalvdline_central_learning_outbox.dart';

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
  bool _loading = true;
  bool _working = false;
  bool _enabled = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _outbox.initialize();
      await _outbox.eligibleLocalDrafts();
      if (!mounted) return;
      setState(() {
        _enabled = _outbox.consentGranted;
        _count = _outbox.pendingCount;
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
        title: Text(next ? 'Contribuire al cervello AI?' : 'Revocare il consenso?'),
        content: Text(next
            ? 'Saranno conservati sul dispositivo soltanto i nuovi '
              'pronostici originali, con partita, mercato, probabilita e '
              'orario. Nessun dato viene inviato al server in questa '
              'versione. Lo storico precedente non verra incluso.'
            : 'La raccolta si fermera e le bozze locali ancora '
              'in attesa saranno cancellate. Le analisi personali '
              'resteranno inalterate.'),
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
              title: const Text('Contributo al cervello AI',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('P23B: raccolta solo locale, nessun invio',
                  style: TextStyle(color: Colors.white70)),
              value: _enabled,
              onChanged: (_loading || _working) ? null : _changeConsent,
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Consenso attivo · $_count previsioni locali in attesa. '
                    'La trasmissione e disattivata.'
                  : 'Disattivato per impostazione predefinita. '
                    'Nessun pronostico viene raccolto per il server.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
