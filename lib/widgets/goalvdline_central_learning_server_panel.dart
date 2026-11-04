import 'package:flutter/material.dart';

import '../services/goalvdline_central_learning_mobile_sync.dart';
import '../services/goalvdline_central_learning_outbox.dart';

/// Strumento manuale di collaudo P23B2B.
/// Non conserva su disco URL, token o autorizzazioni alla trasmissione.
/// Ogni invio e ogni cancellazione richiedono una conferma separata.
class GoalVdLineCentralLearningServerPanel extends StatefulWidget {
  final Future<void> Function()? onLocalChanged;
  const GoalVdLineCentralLearningServerPanel({super.key, this.onLocalChanged});

  @override
  State<GoalVdLineCentralLearningServerPanel> createState() =>
      _GoalVdLineCentralLearningServerPanelState();
}

class _GoalVdLineCentralLearningServerPanelState
    extends State<GoalVdLineCentralLearningServerPanel> {
  final _origin = TextEditingController();
  final _token = TextEditingController();
  final _sync = GoalVdLineCentralLearningMobileSync();
  final _outbox = GoalVdLineCentralLearningOutbox.instance;
  bool _busy = false;
  bool _available = false;
  String _message = 'Collegamento non configurato. Nessun invio automatico.';

  @override
  void dispose() {
    _token.clear();
    _token.dispose();
    _origin.dispose();
    _sync.dispose();
    super.dispose();
  }

  void _show(String text, {bool? available}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      if (available != null) _available = available;
    });
  }

  Future<void> _probe() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final on = await _sync.mobileAvailable(_origin.text);
      _show(
        on
            ? 'Server raggiungibile e invio mobile abilitato.'
            : 'Server non disponibile oppure invio mobile disabilitato.',
        available: on,
      );
    } on FormatException {
      _show(
        'Inserisci un indirizzo HTTPS valido, senza percorsi o parametri.',
        available: false,
      );
    } catch (_) {
      _show('Verifica non riuscita.', available: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String detail, String action) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(detail),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _upload() async {
    if (_busy) return;
    await _outbox.initialize();
    final drafts = await _outbox.eligibleLocalDrafts();
    if (!_outbox.consentGranted || drafts.isEmpty) {
      _show('Prima attiva la raccolta e registra una nuova previsione valida.');
      return;
    }
    if (!await _confirm(
      'Inviare nuove previsioni al server?',
      'Questa operazione trasmette al massimo 20 previsioni originali '
          'relative a non più di 5 partite, con probabilità e mercato. '
          'Non trasmette le copie dello storico precedente. '
          'Il token rimane solo in memoria fino alla fine dell’operazione. '
          'Hai ${drafts.length} previsioni in coda. Procedere?',
      'Invia adesso',
    ))
      return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _sync.uploadOnce(
        baseUrl: _origin.text,
        token: _token.text.trim(),
      );
      _show(result.message);
      if (result.confirmed > 0 && widget.onLocalChanged != null) {
        await widget.onLocalChanged!();
      }
    } on FormatException {
      _show('Indirizzo server HTTPS non valido. Nessun dato inviato.');
    } catch (_) {
      _show('Invio non completato. Verifica la coda e ritenta.');
    } finally {
      _token.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _erase() async {
    if (_busy) return;
    if (!await _confirm(
      'Cancellare i dati del dispositivo dal server?',
      'La cancellazione revoca la credenziale e rimuove i dati centralizzati '
          'associati a quel dispositivo. In caso di successo verrà disattivata '
          'anche la raccolta locale e svuotata la relativa coda. '
          'Lo Storico Analisi e le copie retrospettive non saranno modificati. '
          'Serve una credenziale mobile ancora valida.',
      'Cancella dati remoti',
    ))
      return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _sync.eraseRemote(
        baseUrl: _origin.text,
        token: _token.text.trim(),
      );
      if (result.success) {
        await _outbox.setConsent(false);
        if (widget.onLocalChanged != null) await widget.onLocalChanged!();
      }
      _show(result.message);
    } on FormatException {
      _show('Indirizzo HTTPS non valido. Cancellazione non eseguita.');
    } catch (_) {
      _show(
        'Cancellazione remota non verificabile: richiedi una verifica amministrativa.',
      );
    } finally {
      _token.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: const Text(
        'Collegamento server · test P23B2B',
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: const Text(
        'Manuale: nessun invio automatico',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      ),
      collapsedIconColor: Colors.white70,
      iconColor: Colors.white70,
      children: [
        TextField(
          controller: _origin,
          enabled: !_busy,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server HTTPS (solo indirizzo base)',
            hintText: 'https://nome-server.onrender.com',
            labelStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _token,
          enabled: !_busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Token mobile temporaneo (non amministratore)',
            labelStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          _message,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _probe,
              icon: const Icon(Icons.wifi_tethering, size: 16),
              label: const Text('Verifica server'),
            ),
            FilledButton.icon(
              onPressed: _busy || !_available ? null : _upload,
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Invio manuale'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _erase,
              icon: const Icon(Icons.delete_forever_outlined, size: 16),
              label: const Text('Cancella dal server'),
            ),
          ],
        ),
        const Text(
          'Credenziale solo in memoria e cancellata dopo ogni operazione. '
          'Revocare il consenso locale NON cancella automaticamente i dati '
          'già inviati: utilizzare «Cancella dal server». Se il token è '
          'scaduto o perso, richiedere la cancellazione all’amministratore. '
          'Nessuna sincronizzazione in background.',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}
