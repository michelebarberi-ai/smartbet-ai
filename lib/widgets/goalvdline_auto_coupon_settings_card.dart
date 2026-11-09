import 'package:flutter/material.dart';

import '../services/goalvdline_auto_coupon_preferences.dart';
import '../services/goalvdline_auto_coupon_remote_settings.dart';
import '../services/goalvdline_auto_coupon_today.dart';
import '../services/goalvdline_auto_coupon_push_registration.dart';
import '../services/goalvdline_mobile_token_vault.dart';

/// Fase 5: configurazione locale. Nessun job schedulato e nessuna push
/// vengono attivati finché il relativo servizio remoto non sarà integrato.
class GoalVdLineAutoCouponSettingsCard extends StatefulWidget {
  const GoalVdLineAutoCouponSettingsCard({super.key});

  @override
  State<GoalVdLineAutoCouponSettingsCard> createState() =>
      _GoalVdLineAutoCouponSettingsCardState();
}

class _GoalVdLineAutoCouponSettingsCardState
    extends State<GoalVdLineAutoCouponSettingsCard> {
  final _store = const GoalVdLineAutoCouponPreferencesStore();
  GoalVdLineAutoCouponPreferences _value =
      const GoalVdLineAutoCouponPreferences();
  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;
  bool _checkingToday = false;
  bool _pushBusy = false;
  GoalVdLineTodayCouponResult? _todayResult;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final value = await _store.load();
    if (!mounted) return;
    setState(() {
      _value = value;
      _loading = false;
      _dirty = false;
    });
  }

  void _update(GoalVdLineAutoCouponPreferences value) {
    setState(() {
      _value = value;
      _dirty = true;
    });
  }

  Future<void> _chooseTime() async {
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _value.hour, minute: _value.minute),
      helpText: 'Orario giornaliero AutoSchedina',
    );
    if (chosen == null || !mounted) return;
    _update(_value.copyWith(hour: chosen.hour, minute: chosen.minute));
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    setState(() => _saving = true);
    final saved = await _store.save(_value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Preferenze salvate sul dispositivo. AutoSchedina non è ancora attiva sul server.'
              : 'Salvataggio non riuscito: riprova.',
        ),
      ),
    );
  }

  Future<void> _syncRemote() async {
    if (_syncing || _saving || _dirty || _loading) return;
    setState(() => _syncing = true);
    final service = GoalVdLineAutoCouponRemoteSettings();
    try {
      final token = await GoalVdLineMobileTokenVault().read();
      final message = await service.send(
        preferences: _value,
        token: token ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossibile sincronizzare. Le preferenze locali restano intatte.',
          ),
        ),
      );
    } finally {
      service.dispose();
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _checkToday() async {
    if (_checkingToday || _loading) return;
    setState(() {
      _checkingToday = true;
      _todayResult = null;
    });
    final service = GoalVdLineAutoCouponToday();
    try {
      final token = await GoalVdLineMobileTokenVault().read();
      final result = await service.fetch(token: token ?? '');
      if (mounted) setState(() => _todayResult = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _todayResult = const GoalVdLineTodayCouponResult(
            'Verifica non riuscita. Riprova più tardi.',
          ),
        );
      }
    } finally {
      service.dispose();
      if (mounted) setState(() => _checkingToday = false);
    }
  }

  Future<void> _setPushRegistration(bool enabled) async {
    if (_pushBusy ||
        _loading ||
        _dirty ||
        _saving ||
        (enabled && !_value.requested))
      return;
    setState(() => _pushBusy = true);
    final service = GoalVdLineAutoCouponPushRegistration();
    try {
      final token = await GoalVdLineMobileTokenVault().read();
      final message = enabled
          ? await service.register(token: token ?? '')
          : await service.unregister(token: token ?? '');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Operazione notifiche non riuscita.')),
        );
    } finally {
      service.dispose();
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    const accent = Color(0xFF00C853);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'AutoSchedina AI · configurazione in preparazione',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Queste preferenze vengono salvate solo sull’iPhone. '
            'Le schedine automatiche e le notifiche push non sono ancora attive: '
            'saranno abilitate dopo il collegamento del servizio sul server.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Desidero una schedina ogni giorno',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Preferenza per la futura automazione',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _value.requested,
            onChanged: (enabled) =>
                _update(_value.copyWith(requested: enabled)),
          ),
          const Divider(color: Colors.white12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Orario preferito',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Ora locale del dispositivo',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: Text(
              _value.formattedTime,
              style: const TextStyle(
                color: accent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: _chooseTime,
          ),
          const SizedBox(height: 8),
          Text(
            'Numero eventi: ${_value.events}',
            style: const TextStyle(color: Colors.white),
          ),
          Slider(
            value: _value.events.toDouble(),
            min: 3,
            max: 15,
            divisions: 12,
            label: '${_value.events}',
            onChanged: (next) => _update(_value.copyWith(events: next.round())),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '3 schedine con le stesse partite',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Cambia solo i mercati dove il motore trova alternative valide. '
              'Se non esistono tre varianti attendibili non forza i pronostici.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value:
                _value.systemMode ==
                GoalVdLineAutoCouponPreferences.threeSameFixtures,
            onChanged: (enabled) => _update(
              _value.copyWith(
                systemMode: enabled
                    ? GoalVdLineAutoCouponPreferences.threeSameFixtures
                    : GoalVdLineAutoCouponPreferences.single,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Probabilità minima del mercato: '
            '${_value.minimumMarketProbability}%',
            style: const TextStyle(color: Colors.white),
          ),
          Slider(
            value: _value.minimumMarketProbability.toDouble(),
            min: 50,
            max: 90,
            divisions: 8,
            label: '${_value.minimumMarketProbability}%',
            onChanged: (next) => _update(
              _value.copyWith(minimumMarketProbability: next.round()),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _value.market,
            dropdownColor: const Color(0xFF111827),
            decoration: const InputDecoration(labelText: 'Mercati'),
            items: const [
              DropdownMenuItem(
                value: GoalVdLineAutoCouponPreferences.multiMarket,
                child: Text('Multimercato'),
              ),
              DropdownMenuItem(
                value: GoalVdLineAutoCouponPreferences.overUnder,
                child: Text('Over / Under'),
              ),
              DropdownMenuItem(
                value: GoalVdLineAutoCouponPreferences.goalNoGoal,
                child: Text('Goal / No Goal'),
              ),
              DropdownMenuItem(
                value: GoalVdLineAutoCouponPreferences.oneXTwo,
                child: Text('1X2'),
              ),
            ],
            onChanged: (next) {
              if (next != null) _update(_value.copyWith(market: next));
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Avvisami se la schedina cambia',
              style: TextStyle(color: Colors.white),
            ),
            value: _value.notifyChanges,
            onChanged: (enabled) =>
                _update(_value.copyWith(notifyChanges: enabled)),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving || !_dirty ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Salvataggio…' : 'SALVA PREFERENZE'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading || _dirty || _saving || _syncing
                ? null
                : _syncRemote,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _syncing
                  ? 'Sincronizzazione…'
                  : 'INVIA PREFERENZE AL SERVER (TEST)',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                _loading || _dirty || _saving || _pushBusy || !_value.requested
                ? null
                : () => _setPushRegistration(true),
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(
              _pushBusy
                  ? 'Registrazione…'
                  : 'REGISTRA IPHONE PER NOTIFICHE (TEST)',
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loading || _dirty || _saving || _pushBusy
                ? null
                : () => _setPushRegistration(false),
            icon: const Icon(Icons.notifications_off_outlined),
            label: const Text('Rimuovi registrazione notifiche'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _checkingToday ? null : _checkToday,
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(
              _checkingToday
                  ? 'Controllo in corso…'
                  : 'CONTROLLA SCHEDINA DI OGGI (TEST)',
            ),
          ),
          if (_todayResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _todayResult!.message,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            for (final variant in _todayResult!.coupons) ...[
              const SizedBox(height: 8),
              Text(
                variant.name.replaceAll('_', ' '),
                style: const TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final event in variant.events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Partita #${event.fixtureId} · ${event.market}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Probabilità: ${event.probability.toStringAsFixed(1)}%'
                    '${event.odds == null ? '' : ' · Quota: ${event.odds!.toStringAsFixed(2)}'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
            ],
            if (_todayResult!.coupons.isEmpty)
              for (final event in _todayResult!.events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Partita #${event.fixtureId} · ${event.market}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Probabilità: ${event.probability.toStringAsFixed(1)}%'
                    '${event.odds == null ? '' : ' · Quota: ${event.odds!.toStringAsFixed(2)}'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
          ],
          const Text(
            'Invio volontario: salva soltanto le preferenze. Nessuna schedina o notifica viene ancora generata.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
