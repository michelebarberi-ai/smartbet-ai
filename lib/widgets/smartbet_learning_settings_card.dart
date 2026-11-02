import 'package:flutter/material.dart';

import '../screens/smartbet_learning_overview_screen.dart';
import '../services/smartbet_device_learning_preferences.dart';

/// Unico interruttore operativo per tutte le sezioni collegate.
/// Usa la stessa chiave locale già presente in GoalVdLine: nessuna migrazione.
class SmartBetLearningSettingsCard extends StatefulWidget {
  const SmartBetLearningSettingsCard({super.key});

  @override
  State<SmartBetLearningSettingsCard> createState() =>
      _SmartBetLearningSettingsCardState();
}

class _SmartBetLearningSettingsCardState
    extends State<SmartBetLearningSettingsCard> {
  static const _prefs = SmartBetDeviceLearningPreferences();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _prefs.loadEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = value;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool value) async {
    if (_loading || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await _prefs.saveEnabled(value);
    // Non cambiare l'indicazione prima della conferma della persistenza.
    final actual = await _prefs.loadEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = actual;
      _saving = false;
      _error = saved && actual == value
          ? null
          : 'Impossibile confermare il salvataggio. '
                'Controlla lo stato prima di avviare nuove analisi.';
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text(
              'Apprendimento locale (sperimentale)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Un’unica scelta per GoalVdLine, Combinazioni AI, '
              'Schedina AI, Risultati del giorno e Marcatori AI. '
              'Le correzioni richiedono sempre verifiche sufficienti.',
            ),
            value: _enabled,
            onChanged: _loading || _saving ? null : _setEnabled,
          ),
          if (_loading || _saving) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.query_stats_outlined),
            title: const Text('Statistiche e verifiche'),
            subtitle: const Text('Storico mercati, marcatori e backtest'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const SmartBetLearningOverviewScreen(),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Solo su questo iPhone. Non cancella lo storico e '
              'non attiva un server di apprendimento condiviso.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
