import 'package:flutter/material.dart';
import '../services/bankroll_store.dart';
import '../widgets/ai_card.dart';
import '../widgets/header.dart';
import '../widgets/menu_grid.dart';
import '../widgets/today_card.dart';
import 'bankroll_history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // ============================================================
  // FORMAT
  // ============================================================

  String _money(double value, {bool signed = false}) {
    final sign = signed && value > 0 ? '+' : '';

    return '$sign€${value.toStringAsFixed(2)}';
  }

  String _percent(double value, {bool signed = false}) {
    final sign = signed && value > 0 ? '+' : '';

    return '$sign${value.toStringAsFixed(2)}%';
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
  // DIALOG CAPITALE
  // ============================================================

  Future<void> _showBankrollDialog(
    BuildContext context,
    BankrollStore store,
  ) async {
    final controller = TextEditingController(
      text: store.hasConfiguredBankroll
          ? store.initialBankroll.toStringAsFixed(2)
          : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: Text(
            store.hasConfiguredBankroll
                ? 'Modifica capitale'
                : 'Imposta capitale iniziale',
            style: const TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
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

                final value = double.tryParse(raw);

                if (value == null || value <= 0) {
                  return;
                }

                Navigator.pop(context, value);
              },
              child: const Text('SALVA'),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }

    await store.setInitialBankroll(result);
  }

  // ============================================================
  // CARD STAT
  // ============================================================

  Widget _statCard(IconData icon, String value, String title, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),

            const SizedBox(height: 10),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 5),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SMALL INFO
  // ============================================================

  Widget _smallInfo({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),

          const SizedBox(height: 6),

          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
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
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, child) {
            final snapshot = store.snapshot;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                // =================================================
                // HEADER
                // =================================================
                const HomeHeader(),

                // =================================================
                // AI CARD
                // =================================================
                const AiCard(),

                // =================================================
                // OGGI
                // =================================================
                const TodayCard(),

                const SizedBox(height: 18),

                const Text(
                  'Le tue statistiche',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 18),

                // =================================================
                // NESSUN CAPITALE
                // =================================================
                if (!store.hasConfiguredBankroll)
                  _noBankrollCard(context, store)
                else ...[
                  // ===============================================
                  // CAPITALE
                  // ===============================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: Colors.greenAccent,
                            ),

                            const SizedBox(width: 8),

                            const Expanded(
                              child: Text(
                                'CAPITALE',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),

                            IconButton(
                              tooltip: 'Modifica capitale',
                              onPressed: () {
                                _showBankrollDialog(context, store);
                              },
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Text(
                          _money(snapshot.currentBankroll),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: _smallInfo(
                                title: 'Disponibile',
                                value: _money(snapshot.availableBankroll),
                                color: Colors.greenAccent,
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: _smallInfo(
                                title: 'Impegnato',
                                value: _money(snapshot.lockedBankroll),
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ===============================================
                  // STATISTICHE
                  // ===============================================
                  SizedBox(
                    height: 155,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _statCard(
                          Icons.trending_up,
                          _money(snapshot.totalProfitLoss, signed: true),
                          'Profitto/Perdita',
                          _profitColor(snapshot.totalProfitLoss),
                        ),

                        _statCard(
                          Icons.percent,
                          _percent(snapshot.roiPercent, signed: true),
                          'Rendimento',
                          _profitColor(snapshot.roiPercent),
                        ),

                        _statCard(
                          Icons.pending_actions,
                          '${snapshot.pending}',
                          'In attesa',
                          snapshot.pending > 0
                              ? Colors.orangeAccent
                              : Colors.white70,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ===============================================
                  // RISULTATI
                  // ===============================================
                  Row(
                    children: [
                      Expanded(
                        child: _smallInfo(
                          title: 'Vinte',
                          value: '${snapshot.wins}',
                          color: Colors.greenAccent,
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: _smallInfo(
                          title: 'Perse',
                          value: '${snapshot.losses}',
                          color: Colors.redAccent,
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: _smallInfo(
                          title: 'Annullate',
                          value: '${snapshot.voids}',
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BankrollHistoryScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(
                        snapshot.pending > 0
                            ? 'GESTISCI GIOCATE (${snapshot.pending} IN ATTESA)'
                            : 'STORICO GIOCATE',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.greenAccent,
                        side: BorderSide(
                          color: Colors.greenAccent.withValues(alpha: 0.35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 35),

                const Text(
                  'I tuoi strumenti',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 18),

                const MenuGrid(),

                const SizedBox(height: 25),
              ],
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // CARD NESSUN CAPITALE
  // ============================================================

  Widget _noBankrollCard(BuildContext context, BankrollStore store) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            color: Colors.greenAccent,
            size: 44,
          ),

          const SizedBox(height: 14),

          const Text(
            'Imposta il tuo capitale iniziale',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          const Text(
            'SmartBet utilizzerà questo importo '
            'per calcolare automaticamente gli stake consigliati.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                _showBankrollDialog(context, store);
              },
              icon: const Icon(Icons.add),
              label: const Text('IMPOSTA CAPITALE'),
            ),
          ),
        ],
      ),
    );
  }
}
