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

  Color get confidenceColor {
    if (result.smartScore >= 90) {
      return Colors.green;
    }

    if (result.smartScore >= 80) {
      return Colors.lightGreen;
    }

    if (result.smartScore >= 70) {
      return Colors.orange;
    }

    return Colors.red;
  }

  String get confidenceText {
    if (result.smartScore >= 90) {
      return "ESTREMA";
    }

    if (result.smartScore >= 80) {
      return "ALTA";
    }

    if (result.smartScore >= 70) {
      return "MEDIA";
    }

    return "BASSA";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF111827),
        centerTitle: true,
        title: const Text(
          "SmartBet AI",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    "${match.homeTeam}  vs  ${match.awayTeam}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "${match.league} • ${match.date}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),

              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(24),
              ),

              child: Column(
                children: [
                  const Text(
                    "SMART SCORE",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    "${result.smartScore}",
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),

                  const SizedBox(height: 18),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),

                    child: LinearProgressIndicator(
                      value: result.smartScore / 100,
                      minHeight: 12,
                    ),
                  ),

                  const SizedBox(height: 18),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),

                    decoration: BoxDecoration(
                      color: confidenceColor,
                      borderRadius: BorderRadius.circular(30),
                    ),

                    child: Text(
                      "SMART CONFIDENCE • $confidenceText",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            const Text(
              "PROBABILITÀ AI",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 18),

            _ProbabilityBar(
              title: "🏠 Vittoria Casa",
              value: result.homeProbability,
              color: Colors.green,
            ),

            const SizedBox(height: 14),

            _ProbabilityBar(
              title: "🤝 Pareggio",
              value: result.drawProbability,
              color: Colors.orange,
            ),

            const SizedBox(height: 14),

            _ProbabilityBar(
              title: "✈️ Vittoria Trasferta",
              value: result.awayProbability,
              color: Colors.red,
            ),

            const SizedBox(height: 30),

            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(22),
                    ),

                    child: Column(
                      children: [
                        const Icon(
                          Icons.workspace_premium,
                          color: Colors.amber,
                          size: 34,
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          "VALUE BET",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          result.valueBet,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 18),

                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(22),
                    ),

                    child: Column(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 34,
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          "RISCHIO",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          result.risk,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),
            const Text(
              "🤖 ANALISI SMARTBET AI",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 18),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AnalysisRow(
                    icon: Icons.check_circle,
                    color: Colors.green,
                    text: "Forma recente favorevole",
                  ),

                  const SizedBox(height: 12),

                  _AnalysisRow(
                    icon: Icons.shield,
                    color: Colors.blue,
                    text: "Difesa più solida",
                  ),

                  const SizedBox(height: 12),

                  _AnalysisRow(
                    icon: Icons.home,
                    color: Colors.orange,
                    text: "Fattore campo favorevole",
                  ),

                  const SizedBox(height: 12),

                  _AnalysisRow(
                    icon: Icons.trending_up,
                    color: Colors.green,
                    text: "Smart Score superiore alla media",
                  ),

                  const SizedBox(height: 20),

                  Text(
                    result.explanation,
                    style: const TextStyle(height: 1.5, color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              "📊 CONFRONTO SQUADRE",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  _CompareBar(
                    title: "Attacco",
                    home: result.homeProbability,
                    away: result.awayProbability,
                    color: Colors.green,
                  ),

                  const SizedBox(height: 20),

                  _CompareBar(
                    title: "Difesa",
                    home: result.homeProbability + 10 > 100
                        ? 100
                        : result.homeProbability + 10,
                    away: result.awayProbability,
                    color: Colors.blue,
                  ),

                  const SizedBox(height: 20),

                  _CompareBar(
                    title: "Forma",
                    home: result.smartScore,
                    away: (100 - result.smartScore).clamp(0, 100),
                    color: Colors.orange,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 35),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                icon: const Icon(Icons.auto_graph),
                label: const Text(
                  "ANALISI COMPLETA",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                onPressed: () {},
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _ProbabilityBar extends StatelessWidget {
  final String title;
  final int value;
  final Color color;

  const _ProbabilityBar({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$title   $value%",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),

        const SizedBox(height: 8),

        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 12,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _CompareBar extends StatelessWidget {
  final String title;
  final int home;
  final int away;
  final Color color;

  const _CompareBar({
    required this.title,
    required this.home,
    required this.away,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            SizedBox(
              width: 45,
              child: Text(
                "$home",
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),

            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: home / 100,
                  minHeight: 10,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: away / 100,
                  minHeight: 10,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
                ),
              ),
            ),

            SizedBox(
              width: 45,
              child: Text(
                "$away",
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AnalysisRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _AnalysisRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),

        const SizedBox(width: 12),

        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}
