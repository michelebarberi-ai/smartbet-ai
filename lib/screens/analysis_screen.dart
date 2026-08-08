import 'analysis_detail_screen.dart';
import 'package:flutter/material.dart';
import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
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

          final AnalysisResult result = SmartCore.analyze(match);

          return Card(
            margin: const EdgeInsets.only(bottom: 18),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${match.homeTeam} - ${match.awayTeam}",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    "${match.league} • ${match.date}",
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Icon(Icons.psychology, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        "Smart Score ${result.smartScore}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  LinearProgressIndicator(
                    value: result.smartScore / 100,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(20),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    "Pronostico: ${result.prediction}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  Text("Rischio: ${result.risk}"),

                  const SizedBox(height: 6),

                  Text("Value Bet: ${result.valueBet}"),

                  const SizedBox(height: 14),

                  Text(result.explanation),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AnalysisDetailScreen(
                              match: match,
                              result: result,
                            ),
                          ),
                        );
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
