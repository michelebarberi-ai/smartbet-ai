import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';

class AnalysisDetailScreen extends StatelessWidget {
  final MatchModel match;
  final AnalysisResult result;

  const AnalysisDetailScreen({
    super.key,
    required this.match,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Analisi SmartCore™")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                "${match.homeTeam} - ${match.awayTeam}",
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 10),

            Center(
              child: Text(
                "${match.league} • ${match.date}",
                style: const TextStyle(color: Colors.grey),
              ),
            ),

            const SizedBox(height: 30),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      "🧠 Smart Score™",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    Text(
                      "${result.smartScore}/100",
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),

                    const SizedBox(height: 15),

                    LinearProgressIndicator(
                      value: result.smartScore / 100,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Card(
              child: ListTile(
                leading: const Icon(Icons.sports_soccer),
                title: const Text("Pronostico"),
                subtitle: Text(result.prediction),
              ),
            ),

            Card(
              child: ListTile(
                leading: const Icon(Icons.show_chart),
                title: const Text("Value Bet"),
                subtitle: Text(result.valueBet),
              ),
            ),

            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber),
                title: const Text("Livello di rischio"),
                subtitle: Text(result.risk),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "🤖 Analisi SmartCore",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  result.explanation,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
