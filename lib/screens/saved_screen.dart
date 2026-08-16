import 'package:flutter/material.dart';

import '../services/prediction_store.dart';
import '../services/saved_prediction_store.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final SavedPredictionStore _store = SavedPredictionStore.instance;

  @override
  void initState() {
    super.initState();

    _store.initialize();
  }

  // ============================================================
  // DATA
  // ============================================================

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    final year = date.year.toString();

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year • $hour:$minute';
  }

  // ============================================================
  // SCORE COLOR
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

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> _remove(SavedPrediction item) async {
    await _store.remove(item.fixtureId);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pronostico rimosso dai salvati.')),
    );
  }

  // ============================================================
  // CLEAR
  // ============================================================

  Future<void> _clearAll() async {
    if (_store.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Eliminare tutti?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Tutti i pronostici salvati '
            'verranno eliminati.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text(
                'Elimina',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _store.clear();
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _predictionCard(SavedPrediction item) {
    final scoreColor = _scoreColor(item.smartScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scoreColor.withValues(alpha: 0.20)),
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

              const SizedBox(width: 8),

              IconButton(
                tooltip: 'Rimuovi dai salvati',
                onPressed: () {
                  _remove(item);
                },
                icon: const Icon(Icons.star, color: Colors.amber),
              ),
            ],
          ),

          Text(
            '${item.league} • '
            '${_formatDate(item.matchDate)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),

          const SizedBox(height: 15),

          // ====================================================
          // SCORE / PRONOSTICO
          // ====================================================
          Row(
            children: [
              Expanded(
                child: _infoBox(
                  title: 'SMART SCORE',
                  value: '${item.smartScore}%',
                  color: scoreColor,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _infoBox(
                  title: 'PRONOSTICO',
                  value: item.prediction,
                  color: const Color(0xFF00C853),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _infoBox(
                  title: 'PROB. MAX',
                  value: '${item.bestProbability}%',
                  color: Colors.amber,
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
          // RISCHIO
          // ====================================================
          Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                color: Colors.white38,
                size: 18,
              ),

              const SizedBox(width: 7),

              const Text(
                'Rischio: ',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),

              Expanded(
                child: Text(
                  item.risk,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          // ====================================================
          // STAKE
          // ====================================================
          if (item.shouldBet) ...[
            const SizedBox(height: 14),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00C853).withValues(alpha: 0.20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GIOCATA CONSIGLIATA',
                    style: TextStyle(
                      color: Color(0xFF00C853),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 7),

                  Text(
                    '${item.stakeOutcome} '
                    '@ ${item.stakeOdd.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '${item.stakeBookmaker} • '
                    'Stake '
                    '${item.recommendedStakePercent.toStringAsFixed(2)}%',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
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
  // INFO BOX
  // ============================================================

  Widget _infoBox({
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
  // PROBABILITY
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
            Icon(Icons.star_border, color: Colors.amber, size: 70),

            SizedBox(height: 18),

            Text(
              'Nessun pronostico salvato',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 10),

            Text(
              'I pronostici che salverai '
              'da Pronostico AI '
              'compariranno qui.',
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
          'Pronostici Salvati',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          AnimatedBuilder(
            animation: _store,
            builder: (context, child) {
              if (_store.isEmpty) {
                return const SizedBox.shrink();
              }

              return IconButton(
                tooltip: 'Elimina tutti',
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_outline),
              );
            },
          ),
        ],
      ),

      body: AnimatedBuilder(
        animation: _store,
        builder: (context, child) {
          if (!_store.initialized) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = _store.items;

          if (items.isEmpty) {
            return _emptyState();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFA000), Color(0xFFFF6F00)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.white, size: 32),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pronostici salvati',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),

                          const SizedBox(height: 2),

                          Text(
                            '${_store.count}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              ...items.map(_predictionCard),
            ],
          );
        },
      ),
    );
  }
}
