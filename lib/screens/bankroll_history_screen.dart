import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/bankroll_manager.dart';
import '../services/bankroll_store.dart';

class BankrollHistoryScreen extends StatelessWidget {
  const BankrollHistoryScreen({super.key});

  String _money(double value, {bool signed = false}) {
    final sign = signed && value > 0 ? '+' : '';
    return '$sign€${value.toStringAsFixed(2)}';
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month • $hour:$minute';
  }

  String _statusLabel(BankrollBet bet) {
    if (bet.isWin) return 'VINTA';
    if (bet.isLoss) return 'PERSA';
    if (bet.isVoid) return 'ANNULLATA';
    return 'IN ATTESA';
  }

  Color _statusColor(BankrollBet bet) {
    if (bet.isWin) return Colors.greenAccent;
    if (bet.isLoss) return Colors.redAccent;
    if (bet.isVoid) return Colors.blueGrey;
    return Colors.orangeAccent;
  }

  Future<void> _changeStatus(
    BuildContext context,
    BankrollStore store,
    BankrollBet bet,
    String status,
  ) async {
    final labels = <String, String>{
      'WIN': 'Vinta',
      'LOSS': 'Persa',
      'VOID': 'Annullata',
      'PENDING': 'In attesa',
    };

    final label = labels[status] ?? status;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text(
          'Imposta: $label',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          '${bet.matchLabel}\n\n'
          'Esito giocato: ${bet.outcome} @ ${bet.odd.toStringAsFixed(2)}\n'
          'Importo: ${_money(bet.stakeAmount)}\n\n'
          'Confermi il nuovo stato?',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONFERMA'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final ok = await store.settleAs(bet.id, status);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Giocata aggiornata: $label'
              : 'Impossibile aggiornare la giocata.',
        ),
      ),
    );
  }

  Widget _summary(BankrollStore store) {
    final snapshot = store.snapshot;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryValue(
                  'CAPITALE',
                  _money(snapshot.currentBankroll),
                  Colors.white,
                ),
              ),
              Expanded(
                child: _summaryValue(
                  'DISPONIBILE',
                  _money(snapshot.availableBankroll),
                  Colors.greenAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _summaryValue(
                  'IMPEGNATO',
                  _money(snapshot.lockedBankroll),
                  Colors.orangeAccent,
                ),
              ),
              Expanded(
                child: _summaryValue(
                  'PROFITTO/PERDITA',
                  _money(snapshot.totalProfitLoss, signed: true),
                  snapshot.totalProfitLoss > 0
                      ? Colors.greenAccent
                      : snapshot.totalProfitLoss < 0
                      ? Colors.redAccent
                      : Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Future<void> _shareAllBets(List<BankrollBet> bets) async {
    if (bets.isEmpty) {
      return;
    }

    final text = StringBuffer()
      ..writeln('SMARTBET AI — LE MIE GIOCATE')
      ..writeln()
      ..writeln('${bets.length} giocate registrate')
      ..writeln();

    for (var i = 0; i < bets.length; i++) {
      final bet = bets[i];

      text
        ..writeln('${i + 1}. ${bet.matchLabel}')
        ..writeln(
          '   ${bet.outcome} @ ${bet.odd.toStringAsFixed(2)}'
          ' • ${_money(bet.stakeAmount)}'
          ' • ${_statusLabel(bet)}',
        );

      if (bet.bookmaker.trim().isNotEmpty) {
        text.writeln('   Bookmaker: ${bet.bookmaker}');
      }

      if (!bet.isPending) {
        text.writeln('   P/L: ${_money(bet.profitLoss, signed: true)}');
      }

      text.writeln();
    }

    text.writeln(
      'Analisi statistica a scopo informativo. Gioca responsabilmente.',
    );

    await SharePlus.instance.share(
      ShareParams(
        text: text.toString(),
        subject: 'SmartBet AI — Le mie giocate',
      ),
    );
  }

  Future<void> _shareBet(BankrollBet bet) async {
    final status = _statusLabel(bet);

    final text = StringBuffer()
      ..writeln('SMARTBET AI — GIOCATA REGISTRATA')
      ..writeln()
      ..writeln(bet.matchLabel)
      ..writeln('Mercato: ${bet.outcome}')
      ..writeln('Quota: ${bet.odd.toStringAsFixed(2)}')
      ..writeln('Bookmaker: ${bet.bookmaker}')
      ..writeln('Importo: ${_money(bet.stakeAmount)}')
      ..writeln('Stato: $status');

    if (!bet.isPending) {
      text.writeln(
        'Risultato economico: ${_money(bet.profitLoss, signed: true)}',
      );
    }

    text
      ..writeln()
      ..writeln(
        'Analisi statistica a scopo informativo. Gioca responsabilmente.',
      );

    await SharePlus.instance.share(
      ShareParams(
        text: text.toString(),
        subject: 'SmartBet AI — ${bet.matchLabel}',
      ),
    );
  }

  Future<void> _deleteBet(
    BuildContext context,
    BankrollStore store,
    BankrollBet bet,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Elimina giocata',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${bet.matchLabel}\n\n'
          '${bet.outcome} @ ${bet.odd.toStringAsFixed(2)} • '
          '${_money(bet.stakeAmount)}\n\n'
          'La giocata verrà rimossa definitivamente dallo storico. '
          'Se era già stata chiusa, SmartBet correggerà anche il bankroll.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final ok = await store.deleteBet(bet.id);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Giocata eliminata.' : 'Impossibile eliminare la giocata.',
        ),
      ),
    );
  }

  Widget _betCard(BuildContext context, BankrollStore store, BankrollBet bet) {
    final color = _statusColor(bet);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bet.matchLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(bet),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _date(bet.createdAt),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _detail('ESITO', bet.outcome)),
              Expanded(child: _detail('QUOTA', bet.odd.toStringAsFixed(2))),
              Expanded(child: _detail('IMPORTO', _money(bet.stakeAmount))),
            ],
          ),
          if (bet.bookmaker.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Bookmaker: ${bet.bookmaker}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (!bet.isPending) ...[
            const SizedBox(height: 8),
            Text(
              'Risultato economico: ${_money(bet.profitLoss, signed: true)}',
              style: TextStyle(
                color: bet.profitLoss > 0
                    ? Colors.greenAccent
                    : bet.profitLoss < 0
                    ? Colors.redAccent
                    : Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          Text(
            bet.isPending
                ? 'Registra il risultato della giocata'
                : 'Correggi risultato',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareBet(bet),
                  icon: const Icon(Icons.ios_share_outlined, size: 17),
                  label: const Text('CONDIVIDI'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _deleteBet(context, store, bet),
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('ELIMINA'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusButton(
                context,
                store,
                bet,
                'WIN',
                'VINTA',
                Icons.check_circle_outline,
              ),
              _statusButton(
                context,
                store,
                bet,
                'LOSS',
                'PERSA',
                Icons.cancel_outlined,
              ),
              _statusButton(
                context,
                store,
                bet,
                'VOID',
                'ANNULLATA',
                Icons.remove_circle_outline,
              ),
              if (!bet.isPending)
                _statusButton(
                  context,
                  store,
                  bet,
                  'PENDING',
                  'IN ATTESA',
                  Icons.schedule,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ],
    );
  }

  Widget _statusButton(
    BuildContext context,
    BankrollStore store,
    BankrollBet bet,
    String status,
    String label,
    IconData icon,
  ) {
    return OutlinedButton.icon(
      onPressed: bet.status == status
          ? null
          : () => _changeStatus(context, store, bet, status),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = BankrollStore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Le tue giocate',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, child) {
          final history = store.history.reversed.toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            children: [
              _summary(store),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Storico giocate',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${history.length}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _shareAllBets(history),
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text('CONDIVIDI TUTTE LE GIOCATE'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: Colors.white38,
                        size: 45,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Nessuna giocata registrata',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Quando registri una giocata consigliata da SmartBet '
                        'comparirà qui.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                )
              else
                ...history.map((bet) => _betCard(context, store, bet)),
            ],
          );
        },
      ),
    );
  }
}
