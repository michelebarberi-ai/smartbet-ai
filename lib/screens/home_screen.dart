import 'package:flutter/material.dart';

import '../services/bankroll_store.dart';
import '../widgets/ai_card.dart';
import '../widgets/header.dart';
import '../widgets/menu_grid.dart';
import 'bankroll_history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // ============================================================
  // STAT CARD
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
            final settled = snapshot.wins + snapshot.losses;

            final successRate = settled > 0
                ? (snapshot.wins / settled) * 100.0
                : 0.0;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                const HomeHeader(),
                const AiCard(),

                const SizedBox(height: 18),

                const Text(
                  'Le tue statistiche',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Monitora l’andamento delle giocate registrate '
                  'senza usare un capitale virtuale come elemento centrale.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  height: 145,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statCard(
                        Icons.receipt_long_outlined,
                        '${snapshot.bets}',
                        'Giocate',
                        Colors.white70,
                      ),
                      _statCard(
                        Icons.check_circle_outline,
                        '${snapshot.wins}',
                        'Vinte',
                        Colors.greenAccent,
                      ),
                      _statCard(
                        Icons.cancel_outlined,
                        '${snapshot.losses}',
                        'Perse',
                        Colors.redAccent,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: _smallInfo(
                        title: 'Successo',
                        value: '${successRate.toStringAsFixed(1)}%',
                        color: settled > 0
                            ? Colors.greenAccent
                            : Colors.white54,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _smallInfo(
                        title: 'In attesa',
                        value: '${snapshot.pending}',
                        color: snapshot.pending > 0
                            ? Colors.orangeAccent
                            : Colors.white54,
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

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BankrollHistoryScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: Text(
                      snapshot.pending > 0
                          ? 'LE MIE GIOCATE '
                                '(${snapshot.pending} IN ATTESA)'
                          : 'LE MIE GIOCATE',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                if (snapshot.bets == 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.white54),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Quando registrerai una giocata, '
                            'qui vedrai automaticamente le statistiche '
                            'su vinte, perse e percentuale di successo.',
                            style: TextStyle(
                              color: Colors.white60,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
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
}
