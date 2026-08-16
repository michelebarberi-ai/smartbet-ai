import 'package:flutter/material.dart';

import '../services/prediction_store.dart';
import '../services/saved_prediction_store.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  final PredictionStore _predictionStore = PredictionStore.instance;

  final SavedPredictionStore _savedStore = SavedPredictionStore.instance;

  @override
  void initState() {
    super.initState();

    _savedStore.initialize();
  }

  // ============================================================
  // COLORI
  // ============================================================

  Color _scoreColor(int score) {
    if (score >= 80) {
      return Colors.greenAccent;
    }

    if (score >= 65) {
      return Colors.orangeAccent;
    }

    return Colors.redAccent;
  }

  Color _riskColor(String risk) {
    final value = risk.toLowerCase();

    if (value.contains('basso') || value.contains('low')) {
      return Colors.greenAccent;
    }

    if (value.contains('alto') || value.contains('high')) {
      return Colors.redAccent;
    }

    return Colors.orangeAccent;
  }

  // ============================================================
  // DATA
  // ============================================================

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month • $hour:$minute';
  }

  // ============================================================
  // SALVA / RIMUOVI
  // ============================================================

  Future<void> _toggleSaved(SavedPrediction item) async {
    final wasSaved = _savedStore.isSaved(item.fixtureId);

    await _savedStore.toggle(item);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasSaved ? 'Pronostico rimosso dai salvati.' : 'Pronostico salvato.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _predictionCard(SavedPrediction item) {
    final scoreColor = _scoreColor(item.smartScore);

    final isSaved = _savedStore.isSaved(item.fixtureId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scoreColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ====================================================
          // HEADER
          // ====================================================
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

              const SizedBox(width: 5),

              // =================================================
              // STELLA SALVATAGGIO
              // =================================================
              IconButton(
                tooltip: isSaved ? 'Rimuovi dai salvati' : 'Salva pronostico',
                onPressed: () {
                  _toggleSaved(item);
                },
                icon: Icon(
                  isSaved ? Icons.star : Icons.star_border,
                  color: isSaved ? Colors.amber : Colors.white38,
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Score ${item.smartScore}',
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          Text(
            '${item.league} • '
            '${_formatDate(item.matchDate)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),

          const SizedBox(height: 15),

          // ====================================================
          // PRONOSTICO / PROBABILITÀ / RISCHIO
          // ====================================================
          Row(
            children: [
              Expanded(
                child: _mainBox(
                  title: 'PRONOSTICO',
                  value: item.prediction,
                  color: const Color(0xFF00C853),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _mainBox(
                  title: 'PROB. MAX',
                  value: '${item.bestProbability}%',
                  color: Colors.amber,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _mainBox(
                  title: 'RISCHIO',
                  value: item.risk,
                  color: _riskColor(item.risk),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ====================================================
          // 1 X 2
          // ====================================================
          Row(
            children: [
              Expanded(child: _probabilityBox('1', item.homeProbability)),

              const SizedBox(width: 7),

              Expanded(child: _probabilityBox('X', item.drawProbability)),

              const SizedBox(width: 7),

              Expanded(child: _probabilityBox('2', item.awayProbability)),
            ],
          ),

          const SizedBox(height: 14),

          const Divider(color: Colors.white10),

          const SizedBox(height: 12),

          // ====================================================
          // VALUE BET
          // ====================================================
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.show_chart, color: Colors.amber, size: 18),

              const SizedBox(width: 7),

              Expanded(
                child: Text(
                  item.valueBet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),

          // ====================================================
          // GIOCATA CONSIGLIATA
          // ====================================================
          if (item.shouldBet) ...[
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00C853).withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF00C853),
                    size: 20,
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      '${item.stakeOutcome} '
                      '@ ${item.stakeOdd.toStringAsFixed(2)} '
                      '• ${item.stakeBookmaker}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Text(
                    '${item.recommendedStakePercent.toStringAsFixed(2)}%',
                    style: const TextStyle(
                      color: Color(0xFF00C853),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // MAIN BOX
  // ============================================================

  Widget _mainBox({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 4),

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

  // ============================================================
  // PROBABILITY BOX
  // ============================================================

  Widget _probabilityBox(String label, int probability) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            '$probability%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
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
            Icon(Icons.psychology, color: Color(0xFF00C853), size: 65),

            SizedBox(height: 18),

            Text(
              'Nessun pronostico AI disponibile',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 10),

            Text(
              'I pronostici generati dalle analisi '
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
    return Scaffold(
      backgroundColor: const Color(0xFF111827),

      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Pronostico AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Rimuovi pronostici scaduti',
            onPressed: () {
              _predictionStore.removeExpired();
            },
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),

      // Ascoltiamo entrambi gli store:
      // pronostici + salvati.
      body: ListenableBuilder(
        listenable: Listenable.merge([_predictionStore, _savedStore]),
        builder: (context, child) {
          if (!_savedStore.initialized) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = _predictionStore.items;

          if (items.isEmpty) {
            return _emptyState();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            children: [
              // ================================================
              // RIEPILOGO
              // ================================================
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
                        title: 'Analizzati',
                        value: '${_predictionStore.count}',
                      ),
                    ),

                    Expanded(
                      child: _summaryItem(
                        title: 'Giocabili',
                        value: '${_predictionStore.playableCount}',
                      ),
                    ),

                    Expanded(
                      child: _summaryItem(
                        title: 'Salvati',
                        value: '${_savedStore.count}',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              const Text(
                'Migliori pronostici',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'Ordinati per Smart Score e probabilità',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),

              const SizedBox(height: 14),

              ...items.map(_predictionCard),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // SUMMARY
  // ============================================================

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
