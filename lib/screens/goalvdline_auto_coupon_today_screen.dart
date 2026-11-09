import 'package:flutter/material.dart';

import '../services/goalvdline_auto_coupon_today.dart';
import '../services/goalvdline_mobile_token_vault.dart';

/// Opens only a read-only, authenticated server coupon. Never places bets.
class GoalVdLineAutoCouponTodayScreen extends StatefulWidget {
  const GoalVdLineAutoCouponTodayScreen({super.key, this.load});

  final Future<GoalVdLineTodayCouponResult> Function()? load;

  @override
  State<GoalVdLineAutoCouponTodayScreen> createState() =>
      _GoalVdLineAutoCouponTodayScreenState();
}

class _GoalVdLineAutoCouponTodayScreenState
    extends State<GoalVdLineAutoCouponTodayScreen> {
  GoalVdLineTodayCouponResult? _coupon;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    GoalVdLineTodayCouponResult result;
    try {
      if (widget.load != null) {
        result = await widget.load!();
      } else {
        final service = GoalVdLineAutoCouponToday();
        try {
          final token = await GoalVdLineMobileTokenVault().read();
          result = await service.fetch(token: token ?? '');
        } finally {
          service.dispose();
        }
      }
    } catch (_) {
      result = const GoalVdLineTodayCouponResult(
        'Impossibile leggere la schedina dal server.',
      );
    }
    if (!mounted) return;
    setState(() {
      _coupon = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AutoSchedina del giorno')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(_coupon?.message ?? 'Nessun dato disponibile.'),
                  const SizedBox(height: 12),
                  if (_coupon != null && _coupon!.isReady)
                    for (final event in _coupon!.events)
                      Card(
                        child: ListTile(
                          title: Text(
                            'Partita #${event.fixtureId} · ${event.market}',
                          ),
                          subtitle: Text(
                            'Probabilità ${event.probability.toStringAsFixed(1)}%'
                            ' · ${event.kickoffAt.toLocal().toString().substring(0, 16)}',
                          ),
                          trailing: event.odds == null
                              ? null
                              : Text('Quota ${event.odds!.toStringAsFixed(2)}'),
                        ),
                      ),
                  const SizedBox(height: 12),
                  const Text(
                    'Le probabilità sono stime, non garanzie. Nessuna giocata viene effettuata.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}
