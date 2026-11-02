import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/smartbet_diagnostic_export_service.dart';

/// Esportazione esplicita: nessun invio automatico o accesso al backend.
class SmartBetDiagnosticExportButton extends StatefulWidget {
  const SmartBetDiagnosticExportButton({super.key});

  @override
  State<SmartBetDiagnosticExportButton> createState() =>
      _SmartBetDiagnosticExportButtonState();
}

class _SmartBetDiagnosticExportButtonState
    extends State<SmartBetDiagnosticExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Esportare la diagnostica AI?'),
        content: const Text(
          'Il file JSON contiene pronostici, nomi di squadre e giocatori, '
          'quote, probabilita ed esiti storici. Non contiene credenziali. '
          'Resta sul telefono finche non scegli esplicitamente dove '
          'condividerlo. Non viene inviato automaticamente a ChatGPT.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ESPORTA'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = await const SmartBetDiagnosticExportService().generateFile();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'SmartBet AI - Diagnostica apprendimento',
          text:
              'Report locale SmartBet: analisi, risultati e calibrazioni. '
              'Condividi solo con destinatari di fiducia.',
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossibile preparare il report. Lo storico non e stato modificato.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Crea un file JSON da inviare per controllare errori, '
          'stime e risultati effettivi. Solo dati diagnostici: '
          'nessun invio automatico e nessuna modifica allo storico.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.ios_share_outlined),
          label: Text(
            _busy ? 'Preparazione report...' : 'Esporta diagnostica AI',
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
  );
}
