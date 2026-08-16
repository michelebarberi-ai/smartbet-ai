import 'package:flutter/material.dart';

import '../services/value_bet_store.dart';

class ValueScreen extends StatelessWidget {
  const ValueScreen({super.key});

  // ============================================================
  // COLORI
  // ============================================================

  Color _classificationColor(String classification) {
    switch (classification.toUpperCase().trim()) {
      case 'STRONG VALUE':
        return Colors.greenAccent;

      case 'VALUE':
        return Colors.orangeAccent;

      case 'WEAK VALUE':
        return Colors.amber;

      default:
        return Colors.white54;
    }
  }

  // ============================================================
  // FORMATO DATA
  // ============================================================

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month • $hour:$minute';
  }

  // ============================================================
  // VALUE CARD
  // ============================================================

  Widget _valueCard(SavedValueBet item) {
    final classificationColor = _classificationColor(item.classification);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: classificationColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // HEADER
          // ======================================================
          Row(
            children: [
              Expanded(
                child: Text(
                  item.matchLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: classificationColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item.classification,
                  style: TextStyle(
                    color: classificationColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          Text(
            '${item.league} • ${_formatDate(item.matchDate)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),

          const SizedBox(height: 15),

          // ======================================================
          // PRONOSTICO / QUOTA / STAKE
          // ======================================================
          Row(
            children: [
              Expanded(
                child: _mainBox(
                  title: 'ESITO',
                  value: item.outcome,
                  color: const Color(0xFF00C853),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _mainBox(
                  title: 'QUOTA',
                  value: item.odd.toStringAsFixed(2),
                  color: Colors.amber,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _mainBox(
                  title: 'STAKE',
                  value: item.shouldBet
                      ? '${item.stakePercent.toStringAsFixed(2)}%'
                      : 'NO BET',
                  color: item.shouldBet ? Colors.orangeAccent : Colors.white38,
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // ======================================================
          // BOOKMAKER
          // ======================================================
          Row(
            children: [
              const Icon(
                Icons.account_balance,
                color: Colors.white38,
                size: 18,
              ),

              const SizedBox(width: 7),

              Expanded(
                child: Text(
                  item.bookmaker.trim().isEmpty
                      ? 'Bookmaker non disponibile'
                      : item.bookmaker,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          const Divider(color: Colors.white10, height: 1),

          const SizedBox(height: 15),

          // ======================================================
          // PROBABILITÀ
          // ======================================================
          Row(
            children: [
              Expanded(
                child: _metricBox(
                  title: 'AI',
                  value: '${item.aiProbabilityPercent.toStringAsFixed(1)}%',
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _metricBox(
                  title: 'Mercato',
                  value: '${item.marketProbabilityPercent.toStringAsFixed(1)}%',
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _metricBox(
                  title: 'Quota equa',
                  value: item.fairOdd.toStringAsFixed(2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _metricBox(
                  title: 'Edge',
                  value:
                      '${item.edgePercent >= 0 ? '+' : ''}'
                      '${item.edgePercent.toStringAsFixed(1)} p.p.',
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _metricBox(
                  title: 'EV',
                  value:
                      '${item.expectedValuePercent >= 0 ? '+' : ''}'
                      '${item.expectedValuePercent.toStringAsFixed(1)}%',
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _metricBox(
                  title: 'Confidence AI',
                  value: '${item.aiConfidence}%',
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _metricBox(
                  title: 'Confidence dossier',
                  value: '${item.dossierConfidence}%',
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _metricBox(
                  title: 'Stato',
                  value: item.shouldBet ? 'Giocabile' : 'Non giocabile',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mainBox({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY
  // ============================================================

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, color: Colors.orange, size: 65),

            SizedBox(height: 18),

            Text(
              'Nessuna quota consigliata',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 10),

            Text(
              'Le Value Bet trovate durante le analisi '
              'SmartBet compariranno automaticamente qui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final store = ValueBetStore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),

      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Quote Consigliate',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Rimuovi quote scadute',
            onPressed: () {
              store.removeExpired();
            },
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),

      body: AnimatedBuilder(
        animation: store,
        builder: (context, child) {
          final items = store.items;

          if (items.isEmpty) {
            return _emptyState();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            children: [
              // =================================================
              // RIEPILOGO
              // =================================================
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C853), Color(0xFF009688)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryItem(
                        title: 'Trovate',
                        value: '${store.count}',
                      ),
                    ),

                    Expanded(
                      child: _summaryItem(
                        title: 'Giocabili',
                        value: '${store.playableCount}',
                      ),
                    ),

                    Expanded(
                      child: _summaryItem(
                        title: 'Strong',
                        value: '${store.strongValues.length}',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Migliori opportunità',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'Ordinate per Expected Value',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),

              const SizedBox(height: 14),

              ...items.map(_valueCard),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryItem({required String title, required String value}) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
