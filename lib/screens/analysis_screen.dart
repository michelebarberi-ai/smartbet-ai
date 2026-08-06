import 'package:flutter/material.dart';
import '../models/match_model.dart';
import '../services/match_service.dart';

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<MatchModel> matches = MatchService.getTodayMatches();

    return Scaffold(
      appBar: AppBar(title: const Text("Analisi Partite")),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final match = matches[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${match.homeTeam} - ${match.awayTeam}",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    "${match.league} • ${match.date}",
                    style: const TextStyle(color: Colors.white70),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      const Icon(Icons.psychology, color: Color(0xFF00C853)),

                      const SizedBox(width: 8),

                      Text(
                        "Smart Score™ ${match.smartScore}%",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  LinearProgressIndicator(
                    value: match.smartScore / 100,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(20),
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF00C853),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Probability("1", match.homeWin),
                      _Probability("X", match.draw),
                      _Probability("2", match.awayWin),
                    ],
                  ),

                  const Divider(height: 30),

                  Text(
                    "💎 Value Bet: ${match.valueBet}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 5),

                  Text("Quota ${match.odd.toStringAsFixed(2)}"),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        // Nella prossima sessione apriremo MatchDetailScreen
                      },
                      child: const Text("ANALIZZA"),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Probability extends StatelessWidget {
  final String label;
  final int value;

  const _Probability(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text("$value%"),
      ],
    );
  }
}
