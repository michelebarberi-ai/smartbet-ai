import '../models/match_model.dart';
import '../models/team_analysis.dart';

class StatisticsEngine {
  const StatisticsEngine._();

  // ============================================================
  // VECCHIO METODO
  // ============================================================
  //
  // Lo manteniamo per compatibilità con il progetto.
  //
  static int calculateFromMatch(MatchModel match) {
    int score = 50;

    score += ((match.homeWin - match.awayWin) * 0.35).round();

    if (match.odd >= 1.80 && match.odd <= 2.40) {
      score += 10;
    } else if (match.odd > 2.40) {
      score += 5;
    }

    return score.clamp(1, 99);
  }

  // ============================================================
  // NUOVO SMART SCORE
  // ============================================================

  static int calculateFromTeams({
    required TeamAnalysis homeTeam,
    required TeamAnalysis awayTeam,
    double competitionWeight = 0.70,
  }) {
    // ----------------------------------------------------------
    // FORMA
    // ----------------------------------------------------------

    final formScore = _compare(homeTeam.form, awayTeam.form);

    // ----------------------------------------------------------
    // ATTACCO
    // ----------------------------------------------------------

    final attackScore = _compare(homeTeam.attack, awayTeam.attack);

    // ----------------------------------------------------------
    // DIFESA
    // ----------------------------------------------------------

    final defenseScore = _compare(homeTeam.defense, awayTeam.defense);

    // ----------------------------------------------------------
    // CASA / TRASFERTA
    // ----------------------------------------------------------

    final venueScore = _compare(
      homeTeam.homePerformance,
      awayTeam.awayPerformance,
    );

    // ----------------------------------------------------------
    // MOTIVAZIONE
    // ----------------------------------------------------------

    final motivationScore = _compare(homeTeam.motivation, awayTeam.motivation);

    // ----------------------------------------------------------
    // PESI
    // ----------------------------------------------------------

    final rawScore =
        (formScore * 0.25) +
        (attackScore * 0.20) +
        (defenseScore * 0.20) +
        (venueScore * 0.20) +
        (motivationScore * 0.15);

    // ----------------------------------------------------------
    // PESO DELLA COMPETIZIONE
    // ----------------------------------------------------------

    final weight = competitionWeight.clamp(0.50, 1.00);

    final weightedScore = 50 + ((rawScore - 50) * weight);

    return weightedScore.round().clamp(1, 99);
  }

  // ============================================================
  // CONFRONTO TRA DUE SQUADRE
  // ============================================================

  static double _compare(int home, int away) {
    final total = home + away;

    if (total <= 0) {
      return 50;
    }

    return (home / total) * 100;
  }

  // ============================================================
  // PROBABILITÀ
  // ============================================================

  static Map<String, int> calculateProbabilities({
    required TeamAnalysis homeTeam,
    required TeamAnalysis awayTeam,
  }) {
    final homeStrength = _teamStrength(homeTeam, isHome: true);

    final awayStrength = _teamStrength(awayTeam, isHome: false);

    final difference = homeStrength - awayStrength;

    // Vantaggio del fattore campo.
    final adjustedDifference = difference + 5;

    double homeProbability;
    double awayProbability;
    double drawProbability;

    if (adjustedDifference >= 20) {
      homeProbability = 65;
      awayProbability = 15;
      drawProbability = 20;
    } else if (adjustedDifference >= 10) {
      homeProbability = 52;
      awayProbability = 22;
      drawProbability = 26;
    } else if (adjustedDifference > -10) {
      homeProbability = 38;
      awayProbability = 32;
      drawProbability = 30;
    } else if (adjustedDifference > -20) {
      homeProbability = 25;
      awayProbability = 52;
      drawProbability = 23;
    } else {
      homeProbability = 15;
      awayProbability = 65;
      drawProbability = 20;
    }

    return {
      'home': homeProbability.round(),
      'draw': drawProbability.round(),
      'away': awayProbability.round(),
    };
  }

  // ============================================================
  // FORZA COMPLESSIVA
  // ============================================================

  static double _teamStrength(TeamAnalysis team, {required bool isHome}) {
    final venue = isHome ? team.homePerformance : team.awayPerformance;

    return (team.form * 0.30) +
        (team.attack * 0.25) +
        (team.defense * 0.25) +
        (venue * 0.20);
  }
}
