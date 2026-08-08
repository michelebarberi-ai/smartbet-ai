import '../models/team_analysis.dart';

class TeamAnalyzer {
  static TeamAnalysis analyze({
    required String teamName,
    required int form,
    required int attack,
    required int defense,
    required int homeAway,
    required int motivation,
  }) {
    // Calcolo del Team Score
    final double score =
        (form * 0.30) +
        (attack * 0.25) +
        (defense * 0.20) +
        (homeAway * 0.15) +
        (motivation * 0.10);

    return TeamAnalysis(
      teamName: teamName,
      form: form,
      attack: attack,
      defense: defense,
      homeAway: homeAway,
      motivation: motivation,
      teamScore: score.round(),
    );
  }
}
