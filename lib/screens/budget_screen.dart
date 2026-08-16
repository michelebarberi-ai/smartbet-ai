import 'package:flutter/material.dart';

import '../services/bankroll_manager.dart';
import '../services/bankroll_store.dart';

class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  // ============================================================
  // FORMATTAZIONE
  // ============================================================

  String _money(double value, {bool signed = false}) {
    final sign = signed && value > 0 ? '+' : '';

    return '$sign€${value.toStringAsFixed(2)}';
  }

  String _percent(double value, {bool signed = false}) {
    final sign = signed && value > 0 ? '+' : '';

    return '$sign${value.toStringAsFixed(2)}%';
  }

  String _date(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month • $hour:$minute';
  }

  Color _profitColor(double value) {
    if (value > 0) {
      return Colors.greenAccent;
    }

    if (value < 0) {
      return Colors.redAccent;
    }

    return Colors.white70;
  }

  // ============================================================
  // MODIFICA CAPITALE
  // ============================================================

  Future<void> _changeBankroll(
    BuildContext context,
    BankrollStore store,
  ) async {
    final controller = TextEditingController(
      text: store.currentBankroll > 0
          ? store.currentBankroll.toStringAsFixed(2)
          : '',
    );

    final value = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Imposta capitale',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Capitale in euro',
              prefixText: '€ ',
              labelStyle: TextStyle(color: Colors.white60),
              prefixStyle: TextStyle(color: Colors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.greenAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('ANNULLA'),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim().replaceAll(',', '.');

                final parsed = double.tryParse(raw);

                if (parsed == null || parsed <= 0) {
                  return;
                }

                Navigator.pop(context, parsed);
              },
              child: const Text('SALVA'),
            ),
          ],
        );
      },
    );

    if (value == null) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Conferma modifica',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Impostando un nuovo capitale verranno azzerati '
            'lo storico delle puntate e tutte le statistiche '
            'del bankroll.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('ANNULLA'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('CONFERMA'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    await store.resetBankroll(value);
  }

  // ============================================================
  // SETTLEMENT
  // ============================================================

  Future<void> _settle(
    BuildContext context,
    BankrollStore store,
    BankrollBet bet,
  ) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1F2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Risultato puntata',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  bet.matchLabel,
                  style: const TextStyle(color: Colors.white60),
                ),

                const SizedBox(height: 20),

                _settlementButton(
                  context: context,
                  value: 'WIN',
                  label: 'VINTA',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),

                const SizedBox(height: 10),

                _settlementButton(
                  context: context,
                  value: 'LOSS',
                  label: 'PERSA',
                  icon: Icons.cancel,
                  color: Colors.redAccent,
                ),

                const SizedBox(height: 10),

                _settlementButton(
                  context: context,
                  value: 'VOID',
                  label: 'ANNULLATA',
                  icon: Icons.remove_circle_outline,
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    if (result == 'WIN') {
      await store.settleWin(bet.id);
    }

    if (result == 'LOSS') {
      await store.settleLoss(bet.id);
    }

    if (result == 'VOID') {
      await store.settleVoid(bet.id);
    }
  }

  Widget _settlementButton({
    required BuildContext context,
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context, value);
        },
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  // ============================================================
  // CARD STATISTICA
  // ============================================================

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),

            const SizedBox(height: 8),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 4),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STORICO
  // ============================================================

  Widget _betCard(BuildContext context, BankrollStore store, BankrollBet bet) {
    Color statusColor;
    String statusLabel;

    if (bet.isWin) {
      statusColor = Colors.greenAccent;
      statusLabel = 'VINTA';
    } else if (bet.isLoss) {
      statusColor = Colors.redAccent;
      statusLabel = 'PERSA';
    } else if (bet.isVoid) {
      statusColor = Colors.blueGrey;
      statusLabel = 'ANNULLATA';
    } else {
      statusColor = Colors.orangeAccent;
      statusLabel = 'IN ATTESA';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white10),
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
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            _date(bet.createdAt),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(child: _betValue('Esito', bet.outcome)),

              Expanded(child: _betValue('Quota', bet.odd.toStringAsFixed(2))),

              Expanded(child: _betValue('Stake', _money(bet.stakeAmount))),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  bet.bookmaker,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),

              if (!bet.isPending)
                Text(
                  _money(bet.profitLoss, signed: true),
                  style: TextStyle(
                    color: _profitColor(bet.profitLoss),
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),

          if (bet.isPending) ...[
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _settle(context, store, bet);
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('INSERISCI RISULTATO'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _betValue(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),

        const SizedBox(height: 3),

        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final store = BankrollStore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Budget',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, child) {
          final snapshot = store.snapshot;

          final history = store.history.reversed.toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            children: [
              // =================================================
              // CAPITALE
              // =================================================
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C853), Color(0xFF009688)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CAPITALE ATTUALE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _money(snapshot.currentBankroll),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: _topValue(
                            'Disponibile',
                            _money(snapshot.availableBankroll),
                          ),
                        ),

                        Expanded(
                          child: _topValue(
                            'Impegnato',
                            _money(snapshot.lockedBankroll),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _changeBankroll(context, store);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('MODIFICA CAPITALE'),
                ),
              ),

              const SizedBox(height: 24),

              // =================================================
              // PERFORMANCE
              // =================================================
              const Text(
                'Performance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  _statCard(
                    title: 'Profitto/Perdita',
                    value: _money(snapshot.totalProfitLoss, signed: true),
                    icon: Icons.trending_up,
                    color: _profitColor(snapshot.totalProfitLoss),
                  ),

                  const SizedBox(width: 10),

                  _statCard(
                    title: 'Rendimento',
                    value: _percent(snapshot.roiPercent, signed: true),
                    icon: Icons.percent,
                    color: _profitColor(snapshot.roiPercent),
                  ),

                  const SizedBox(width: 10),

                  _statCard(
                    title: 'Crescita',
                    value: _percent(
                      snapshot.bankrollGrowthPercent,
                      signed: true,
                    ),
                    icon: Icons.account_balance_wallet_outlined,
                    color: _profitColor(snapshot.bankrollGrowthPercent),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  _statCard(
                    title: 'Vinte',
                    value: '${snapshot.wins}',
                    icon: Icons.check_circle,
                    color: Colors.greenAccent,
                  ),

                  const SizedBox(width: 10),

                  _statCard(
                    title: 'Perse',
                    value: '${snapshot.losses}',
                    icon: Icons.cancel,
                    color: Colors.redAccent,
                  ),

                  const SizedBox(width: 10),

                  _statCard(
                    title: 'In attesa',
                    value: '${snapshot.pending}',
                    icon: Icons.pending_actions,
                    color: Colors.orangeAccent,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // =================================================
              // ESPOSIZIONE
              // =================================================
              const Text(
                'Esposizione',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Column(
                  children: [
                    _infoRow(
                      'Capitale iniziale',
                      _money(snapshot.initialBankroll),
                    ),

                    _infoRow(
                      'Totale puntato',
                      _money(snapshot.totalStakePlaced),
                    ),

                    _infoRow(
                      'Stake concluso',
                      _money(snapshot.settledStakeForRoi),
                    ),

                    _infoRow(
                      'Capitale impegnato',
                      _money(snapshot.lockedBankroll),
                    ),

                    _infoRow('Puntate totali', '${snapshot.bets}'),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // =================================================
              // STORICO
              // =================================================
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Storico puntate',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Text(
                    '${history.length}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.history, color: Colors.white38, size: 40),
                      SizedBox(height: 10),
                      Text(
                        'Nessuna puntata registrata',
                        style: TextStyle(color: Colors.white60),
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

  Widget _topValue(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white54)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
