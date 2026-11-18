import 'package:flutter/material.dart';

import '../services/goalvdline_palinsesto_digest_preferences.dart';

/// Configuration for the future server-sent daily *fixture* digest.
/// Never schedules a coupon or claims that APNs is activated by a local save.
class GoalVdLinePalinsestoDigestSettingsCard extends StatefulWidget {
  const GoalVdLinePalinsestoDigestSettingsCard({super.key});

  @override
  State<GoalVdLinePalinsestoDigestSettingsCard> createState() =>
      _GoalVdLinePalinsestoDigestSettingsCardState();
}

class _GoalVdLinePalinsestoDigestSettingsCardState
    extends State<GoalVdLinePalinsestoDigestSettingsCard> {
  final _store = const GoalVdLinePalinsestoDigestPreferencesStore();
  GoalVdLinePalinsestoDigestPreferences _preferences =
      const GoalVdLinePalinsestoDigestPreferences();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final value = await _store.load();
    if (!mounted) return;
    setState(() {
      _preferences = value;
      _loading = false;
    });
  }

  Future<void> _save(GoalVdLinePalinsestoDigestPreferences value) async {
    if (_loading || _saving) return;
    setState(() => _saving = true);
    final success = await _store.save(value);
    if (!mounted) return;
    setState(() {
      if (success) _preferences = value;
      _saving = false;
    });
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossibile salvare la preferenza di notifica.'),
      ));
    }
  }

  Future<void> _chooseTime() async {
    if (_saving || _loading) return;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _preferences.hour, minute: _preferences.minute),
      helpText: 'Orario del riepilogo del palinsesto',
      confirmText: 'CONFERMA',
      cancelText: 'ANNULLA',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    await _save(_preferences.copyWith(
      hour: selected.hour, minute: selected.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('b72-daily-fixture-digest-settings'),
      margin: EdgeInsets.zero,
      color: const Color(0xFF1F2937),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Riepilogo quotidiano del palinsesto',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Una notifica con quante partite e quali campionati '
              'sono in programma. Non genera automaticamente schedine '
              'e non avvia pronostici o ricerche di quote.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            SwitchListTile(
              key: const Key('b72-request-daily-fixture-digest'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Vorrei ricevere il riepilogo ogni mattina'),
              value: _preferences.requested,
              onChanged: _loading || _saving ? null :
                  (enabled) => _save(_preferences.copyWith(requested: enabled)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Orario preferito (Italia)'),
              subtitle: const Text('Ora italiana · Europa/Roma'),
              trailing: Text(
                _preferences.formattedHour,
                key: const Key('b72-daily-fixture-digest-time'),
              ),
              onTap: _loading || _saving ? null : _chooseTime,
            ),
            const Text(
              'Configurazione in preparazione: il salvataggio su iPhone '
              'non attiva ancora la notifica push. Occorre completare '
              'la registrazione APNs e il servizio remoto.',
              key: Key('b72-digest-push-not-yet-active'),
              style: TextStyle(fontSize: 11, color: Colors.amberAccent),
            ),
            if (_saving || _loading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
