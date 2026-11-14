import 'package:flutter/material.dart';
import '../services/goalvdline_coupon_ready_notifier.dart';

/// Abilitazione esplicita, indipendente dall'AutoSchedina remota.
class GoalVdLineCouponReadyNotificationCard extends StatefulWidget {
  const GoalVdLineCouponReadyNotificationCard({super.key});

  @override
  State<GoalVdLineCouponReadyNotificationCard> createState() =>
      _GoalVdLineCouponReadyNotificationCardState();
}

class _GoalVdLineCouponReadyNotificationCardState
    extends State<GoalVdLineCouponReadyNotificationCard> {
  final _notifier = const GoalVdLineCouponReadyNotifier();
  bool _enabled = false;
  bool _loading = true;
  GoalVdLineNotificationStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _notifier.isEnabled();
    final status = await _notifier.notificationStatus();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _status = status;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_loading) return;
    setState(() => _loading = true);
    final enabled = await _notifier.setEnabled(value);
    final status = await _notifier.notificationStatus();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _status = status;
      _loading = false;
    });
    if (value && !enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Notifiche non autorizzate su questo dispositivo. '
          'Verifica Impostazioni iPhone > Notifiche.',
        )),
      );
    }
  }

  Future<void> _sendTest() async {
    if (_loading || !_enabled) return;
    setState(() => _loading = true);
    final sent = await _notifier.sendTestNotification();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sent
          ? 'Notifica di prova programmata. Controlla il banner '
              'e il Centro Notifiche dell’iPhone.'
          : 'Notifica di prova non programmata. Controlla '
              'Impostazioni iPhone > Notifiche > GoalVdLine.')),
    );
  }

  Future<void> _refreshStatus() async {
    if (_loading) return;
    setState(() => _loading = true);
    final status = await _notifier.notificationStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _sendLockScreenTest() async {
    if (_loading || !_enabled) return;
    setState(() => _loading = true);
    final scheduled = await _notifier.sendLockScreenTestNotification();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(scheduled
          ? 'Prova programmata: blocca subito l’iPhone. '
              'La notifica dovrebbe partire dopo 15 secondi. '
              'Non verifica la generazione con app sospesa.'
          : 'Prova non programmata: controlla il permesso '
              'notifiche nelle Impostazioni iPhone.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
      key: const Key('b45-on-demand-ready-notification'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Avvisami quando la schedina è pronta'),
      subtitle: const Text(
        'Notifica locale dopo una schedina creata su richiesta. '
        'Non attiva la generazione giornaliera né consuma un server aggiuntivo.',
      ),
      value: _enabled,
      onChanged: _loading ? null : _toggle,
        ),
        if (_enabled) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'La notifica di schedina pronta arriva soltanto se '
              'la generazione termina con almeno una selezione valida. '
              'Attivare il consenso non avvia analisi automatiche.',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ),
          if (_status != null)
            Padding(
              key: const Key('b49-ios-notification-status'),
              padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 4,
              ),
              child: Text(
                _status!.italianSummary,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ),
          TextButton.icon(
            key: const Key('b49-refresh-notification-status'),
            onPressed: _loading ? null : _refreshStatus,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('VERIFICA PERMESSI iOS'),
          ),
          TextButton.icon(
            key: const Key('b45-send-local-test-notification'),
            onPressed: _loading ? null : _sendTest,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('INVIA NOTIFICA DI PROVA'),
          ),
          TextButton.icon(
            key: const Key('b49-lock-screen-notification-test'),
            onPressed: _loading ? null : _sendLockScreenTest,
            icon: const Icon(Icons.lock_clock_outlined),
            label: const Text('PROVA CON IPHONE BLOCCATO (15 SEC)'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Questa prova verifica solo la consegna locale con '
              'schermo bloccato. Se iOS sospende la generazione '
              'sul telefono, non puo essere emessa una notifica '
              'di completamento: serve un job remoto con push APNs.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ),
        ],
      ],
    );
  }
}
