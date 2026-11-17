import 'package:flutter/material.dart';

/// Local, foreground-only snapshot from the fixture provider.
/// A scheduled match is NOT yet an AI-confirmed reliable prediction.
class GoalVdLineDailyMatchesCard extends StatelessWidget {
  const GoalVdLineDailyMatchesCard({
    super.key,
    required this.count,
    this.totalCount,
    required this.loading,
    required this.onCreateCoupon,
  });

  final int? count;
  final int? totalCount;
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
                ? 'Nessuna partita futura ricevuta dal provider per oggi.'
                : '$count partite future disponibili nel calendario di oggi.';

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
            if (!loading && totalCount != null && totalCount != count) ...[
              const SizedBox(height: 5),
              Text(
                'Totale incontri futuri nel feed di oggi: $totalCount.',
                key: const Key('b63-daily-total-count'),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 7),
            const Text(
              'Tutte le competizioni sono incluse nel calendario. '
              'Il Palinsesto Italia nella Schedina AI controlla '
              'facoltativamente la presenza di quote per le singole '
              'partite, non il nome del campionato. '
              'Il conteggio non significa che tutti gli incontri abbiano '
              'un pronostico affidabile. '
              'La quota sopra 1,20 viene verificata soltanto '
              'per il mercato selezionato dopo l\'analisi sportiva.',
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
