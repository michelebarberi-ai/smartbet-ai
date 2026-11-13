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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _notifier.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_loading) return;
    setState(() => _loading = true);
    final enabled = await _notifier.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
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

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const Key('b45-on-demand-ready-notification'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Avvisami quando la schedina è pronta'),
      subtitle: const Text(
        'Notifica locale dopo una schedina creata su richiesta. '
        'Non attiva la generazione giornaliera né consuma un server aggiuntivo.',
      ),
      value: _enabled,
      onChanged: _loading ? null : _toggle,
    );
  }
}
