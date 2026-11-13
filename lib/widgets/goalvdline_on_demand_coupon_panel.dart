import 'package:flutter/material.dart';

import '../services/goalvdline_mobile_token_vault.dart';
import '../services/goalvdline_on_demand_coupon_client.dart';

/// B47 - Explicit, staging-gated on-demand server mode.
/// The normal local Schedina flow remains untouched and available.
class GoalVdLineOnDemandCouponPanel extends StatefulWidget {
  const GoalVdLineOnDemandCouponPanel({
    super.key,
    required this.events,
    required this.minimumProbability,
    this.client,
    this.tokenVault,
  });

  final int events;
  final int minimumProbability;
  final GoalVdLineOnDemandCouponClient? client;
  final GoalVdLineMobileTokenVault? tokenVault;

  @override
  State<GoalVdLineOnDemandCouponPanel> createState() =>
      _GoalVdLineOnDemandCouponPanelState();
}

class _GoalVdLineOnDemandCouponPanelState
    extends State<GoalVdLineOnDemandCouponPanel>
    with WidgetsBindingObserver {
  late final GoalVdLineOnDemandCouponClient _client;
  late final bool _ownsClient;
  late final GoalVdLineMobileTokenVault _vault;

  bool _visible = false;
  bool _busy = false;
  String? _message;
  GoalVdLineOnDemandStatus? _result;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? GoalVdLineOnDemandCouponClient();
    _vault = widget.tokenVault ?? GoalVdLineMobileTokenVault();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsClient) _client.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible && !_busy) {
      _refresh();
    }
  }

  Future<String?> _token() => _vault.read();

  Future<void> _initialize() async {
    final enabled = await _client.available();
    if (!mounted || !enabled) return;
    setState(() => _visible = true);
    final existing = await _client.lastRequest();
    if (!mounted) return;
    if (existing?['jobId'] is String) {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final saved = await _client.lastRequest();
    if (!mounted || saved?['jobId'] is! String) return;
    final token = await _token();
    if (!mounted) return;
    if (token == null) {
      setState(() => _message =
          'Salva prima il token mobile nel pannello del cervello centrale.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final value = await _client.fetch(
      token: token, jobId: saved!['jobId'] as String,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = value;
      if (value.status == 'error') _message = value.message;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final token = await _token();
    if (!mounted) return;
    if (token == null) {
      setState(() => _message =
          'Per questa modalità serve la credenziale mobile del cervello centrale.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    // Separate, explicitly initiated mode: never replace the local button,
    // never start scheduled AutoSchedina, and never auto-resubmit.
    final value = await _client.submit(
      token: token,
      events: widget.events,
      minimumMarketProbability: widget.minimumProbability,
      market: 'MULTI',
      systemMode: 'THREE_SAME_FIXTURES',
      windowDays: 1,
      // A second generation is only initiated by a fresh tap here.
      // A network error does not silently create a new (possibly paid) job.
      forceNew: _result?.isReady == true ||
          _result?.status == 'failed' ||
          _result?.status == 'no_coupon' ||
          (_result?.status == 'error' &&
              (_result?.message == 'Richiesta scaduta.' ||
               _result?.message == 'Richiesta non trovata.')),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = value;
      if (value.status == 'error') _message = value.message;
    });
  }

  String _label(String? status) {
    switch (status) {
      case 'queued':
        return 'IN CODA · calcolo sul server non ancora iniziato';
      case 'running':
        return 'IN ELABORAZIONE · puoi bloccare l’iPhone';
      case 'ready':
        return 'SCHEDINA PRONTA · risultato recuperato dal server';
      case 'no_coupon':
        return 'NESSUNA SCHEDINA QUOTATA DISPONIBILE';
      case 'failed':
        return 'ELABORAZIONE NON RIUSCITA';
      default:
        return 'Pronta per una richiesta esplicita';
    }
  }

  String _formatOdds(Object? source) =>
      source is num && source.isFinite && source > 1.20
          ? source.toStringAsFixed(2)
          : 'N/D';

  Widget _couponEvents(Object? raw) {
    if (raw is! List || raw.length < 3 || raw.length > 15) {
      return const Text('Risultato remoto non verificabile.',
          style: TextStyle(color: Colors.orangeAccent));
    }
    return Column(
      children: [
        for (final item in raw)
          if (item is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(
                    '${item['fixtureId'] ?? '?'} · ${item['market'] ?? 'N/D'}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  )),
                  const SizedBox(width: 10),
                  Text(
                    '${item['marketProbability'] ?? 'N/D'}% · ${_formatOdds(item['odds'])}',
                    style: const TextStyle(
                      color: Color(0xFF69F0AE), fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _resultWidgets(GoalVdLineOnDemandStatus result) {
    final coupon = result.coupon;
    if (!result.isReady || coupon == null) {
      return const SizedBox.shrink();
    }
    final variants = coupon['coupons'];
    if (variants is List && variants.length == 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final variant in variants)
            if (variant is Map) ...[
              const SizedBox(height: 10),
              Text('${variant['name'] ?? 'SCHEDINA'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  )),
              _couponEvents(variant['events']),
              const Divider(color: Colors.white24),
            ],
        ],
      );
    }
    return _couponEvents(coupon['events']);
  }

  @override
  Widget build(BuildContext context) {
    // This UI never appears when Render has not enabled remote requests.
    if (!_visible) return const SizedBox.shrink();
    final result = _result;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ELABORAZIONE SERVER · BETA',
              style: TextStyle(
                color: Color(0xFF69F0AE),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              )),
          const SizedBox(height: 6),
          const Text(
            'Modalità opzionale: 3 schedine con le stesse partite, '
            'oggi, e quote reali >1,20. Il calcolo continua sul server '
            'anche quando chiudi l’app. '
            'Non applica ancora tutti i filtri locali né il confronto Diego: '
            'la creazione tradizionale resta disponibile.',
            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(_label(result?.status),
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (_message != null) ...[
            const SizedBox(height: 7),
            Text(_message!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy || result?.isPending == true ? null : _submit,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(_busy
                    ? 'VERIFICA...'
                    : result?.isReady == true
                        ? 'NUOVA SCHEDINA SUL SERVER'
                        : 'CREA SUL SERVER'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('RECUPERA RISULTATO'),
              ),
            ],
          ),
          if (result?.isReady == true) ...[
            const SizedBox(height: 14),
            _resultWidgets(result!),
          ],
        ],
      ),
    );
  }
}
