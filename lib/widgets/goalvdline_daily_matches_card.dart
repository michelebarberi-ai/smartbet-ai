import 'package:flutter/material.dart';

/// Local, foreground-only snapshot from the fixture provider.
/// A scheduled match is NOT yet an AI-confirmed reliable prediction.
class GoalVdLineDailyMatchesCard extends StatelessWidget {
  const GoalVdLineDailyMatchesCard({
    super.key,
    required this.count,
    required this.loading,
    required this.onCreateCoupon,
  });

  final int? count;
  final bool loading;
  final VoidCallback onCreateCoupon;

  @override
  Widget build(BuildContext context) {
    final value = loading ? '…' : count?.toString() ?? 'N/D';
    final message = loading
        ? 'Aggiornamento del palinsesto in corso.'
        : count == null
            ? 'Partite non disponibili: verifica la connessione e aggiorna.'
            : count == 0
                ? 'Nessuna partita futura compatibile con il palinsesto Italia oggi.'
                : '$count partite future disponibili per l’analisi AI oggi.';

    return Card(
      key: const Key('b45-daily-matches'),
      margin: const EdgeInsets.only(bottom: 14),
      color: const Color(0xFF1F2937),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: Color(0xFF00C853)),
                SizedBox(width: 9),
                Expanded(
                  child: Text('PARTITE DA ANALIZZARE OGGI',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(value,
              key: const Key('b45-daily-count'),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00C853),
              ),
            ),
            Text(message),
            const SizedBox(height: 7),
            const Text(
              'Conteggio aggiornato all’apertura e al refresh della Home. '
              'Solo partite non iniziate: non significa che abbiano già '
              'un pronostico affidabile o una quota Sisal disponibile.',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreateCoupon,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('ANALIZZA LE PARTITE'),
            ),
          ],
        ),
      ),
    );
  }
}
