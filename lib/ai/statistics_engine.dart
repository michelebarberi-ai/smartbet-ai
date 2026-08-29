import 'dart:math' as math;

import '../models/match_model.dart';
import '../models/team_analysis.dart';
import '../services/team_form_service.dart';

class StatisticsEngine {
  const StatisticsEngine._();

  // ============================================================
  // VECCHIO METODO
  // ============================================================
  //
  // Lo manteniamo per compatibilità con il progetto.
  // ============================================================

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
  // SMART SCORE
  // ============================================================

  static int calculateFromTeams({
    required TeamAnalysis homeTeam,
    required TeamAnalysis awayTeam,
    double competitionWeight = 0.70,
  }) {
    // ============================================================
    // SMART SCORE
    // ============================================================
    //
    // Lo Smart Score misura l'AFFIDABILITÀ del quadro statistico,
    // non quale squadra è favorita.
    //
    // Consideriamo:
    // - intensità delle differenze tra le squadre;
    // - concordanza dei diversi indicatori;
    // - peso/affidabilità della competizione.
    //
    // Un vantaggio forte dell'ospite può quindi produrre uno
    // Smart Score alto esattamente come un vantaggio forte della casa.
    // ============================================================

    final formScore = _compare(homeTeam.form, awayTeam.form);
    final attackScore = _compare(homeTeam.attack, awayTeam.attack);
    final defenseScore = _compare(homeTeam.defense, awayTeam.defense);
    final venueScore = _compare(
      homeTeam.homePerformance,
      awayTeam.awayPerformance,
    );
    final motivationScore = _compare(homeTeam.motivation, awayTeam.motivation);

    final factors = <({double score, double weight})>[
      (score: formScore, weight: 0.25),
      (score: attackScore, weight: 0.20),
      (score: defenseScore, weight: 0.20),
      (score: venueScore, weight: 0.20),
      (score: motivationScore, weight: 0.15),
    ];

    // Direzione complessiva del confronto.
    final directionalScore =
        (formScore * 0.25) +
        (attackScore * 0.20) +
        (defenseScore * 0.20) +
        (venueScore * 0.20) +
        (motivationScore * 0.15);

    final homeFavored = directionalScore >= 50;

    // ------------------------------------------------------------
    // FORZA DEL SEGNALE
    // ------------------------------------------------------------
    //
    // 50 = equilibrio.
    // Più un fattore si allontana da 50, più è informativo.
    // Usiamo il valore assoluto perché non importa se favorisca
    // casa o trasferta.
    // ------------------------------------------------------------

    var signalStrength = 0.0;

    for (final factor in factors) {
      final distance = (factor.score - 50).abs() * 2;
      signalStrength += distance.clamp(0.0, 100.0) * factor.weight;
    }

    // ------------------------------------------------------------
    // CONCORDANZA DEI SEGNALI
    // ------------------------------------------------------------
    //
    // Un pronostico è più affidabile quando forma, attacco,
    // difesa, venue e motivazione puntano nella stessa direzione.
    //
    // I fattori quasi neutrali non vengono considerati come
    // conferme forti.
    // ------------------------------------------------------------

    var activeWeight = 0.0;
    var agreeingWeight = 0.0;

    for (final factor in factors) {
      final distance = (factor.score - 50).abs();

      if (distance < 4) {
        continue;
      }

      activeWeight += factor.weight;

      final favorsHome = factor.score > 50;

      if (favorsHome == homeFavored) {
        agreeingWeight += factor.weight;
      }
    }

    final agreement = activeWeight <= 0 ? 0.5 : agreeingWeight / activeWeight;

    // ------------------------------------------------------------
    // SCORE BASE
    // ------------------------------------------------------------

    var confidence = 45.0 + (signalStrength * 0.35) + (agreement * 20.0);

    // Se gli indicatori sono molto discordanti, limitiamo
    // l'eccessiva sicurezza.
    if (agreement < 0.55) {
      confidence -= 8;
    } else if (agreement < 0.70) {
      confidence -= 4;
    }

    // ------------------------------------------------------------
    // PESO DELLA COMPETIZIONE
    // ------------------------------------------------------------

    final weight = competitionWeight.clamp(0.50, 1.00);

    confidence = 45 + ((confidence - 45) * weight);

    return confidence.round().clamp(1, 99);
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
  // PROBABILITÀ 1X2
  // ============================================================
  //
  // IMPORTANTE:
  // questa logica rimane invariata.
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
  // MERCATI GOL
  // ============================================================
  //
  // Restituisce:
  //
  // over15   -> Over 1.5
  // under15  -> Under 1.5
  // over25   -> Over 2.5
  // under25  -> Under 2.5
  // goal     -> entrambe segnano / BTTS YES
  // noGoal   -> almeno una non segna / BTTS NO
  //
  // Il calcolo utilizza:
  //
  // - gol segnati recenti
  // - gol subiti recenti
  // - numero partite disponibili
  //
  // e costruisce una stima dei gol attesi.
  // ============================================================

  static Map<String, int> calculateGoalMarketProbabilities({
    required TeamFormData homeForm,
    required TeamFormData awayForm,
  }) {
    if (homeForm.matchesPlayed <= 0 || awayForm.matchesPlayed <= 0) {
      return {
        'over15': 0,
        'under15': 0,
        'over25': 0,
        'under25': 0,
        'goal': 0,
        'noGoal': 0,
      };
    }

    // ==========================================================
    // MEDIE RECENTI
    // ==========================================================

    final homeGoalsForAverage = homeForm.goalsFor / homeForm.matchesPlayed;

    final homeGoalsAgainstAverage =
        homeForm.goalsAgainst / homeForm.matchesPlayed;

    final awayGoalsForAverage = awayForm.goalsFor / awayForm.matchesPlayed;

    final awayGoalsAgainstAverage =
        awayForm.goalsAgainst / awayForm.matchesPlayed;

    // ==========================================================
    // EXPECTED GOALS
    // ==========================================================
    //
    // Casa:
    // 55% capacità offensiva della squadra di casa
    // 45% vulnerabilità difensiva dell'avversaria
    //
    // Trasferta:
    // stesso principio.
    //
    // Applichiamo un piccolo vantaggio campo.
    // ==========================================================

    var expectedHomeGoals =
        (homeGoalsForAverage * 0.55) + (awayGoalsAgainstAverage * 0.45);

    var expectedAwayGoals =
        (awayGoalsForAverage * 0.55) + (homeGoalsAgainstAverage * 0.45);

    // Piccolo fattore campo.
    expectedHomeGoals *= 1.06;
    expectedAwayGoals *= 0.96;

    // Evitiamo stime matematicamente estreme
    // in presenza di campioni molto piccoli.
    expectedHomeGoals = expectedHomeGoals.clamp(0.20, 3.50);

    expectedAwayGoals = expectedAwayGoals.clamp(0.15, 3.25);

    final totalExpectedGoals = expectedHomeGoals + expectedAwayGoals;

    // ==========================================================
    // DISTRIBUZIONE DI POISSON
    // ==========================================================

    final probability0Goals = _poissonProbability(
      lambda: totalExpectedGoals,
      goals: 0,
    );

    final probability1Goal = _poissonProbability(
      lambda: totalExpectedGoals,
      goals: 1,
    );

    final probability2Goals = _poissonProbability(
      lambda: totalExpectedGoals,
      goals: 2,
    );

    // ==========================================================
    // OVER / UNDER 1.5
    // ==========================================================
    //
    // Under 1.5 = probabilità di 0 o 1 gol.
    // ==========================================================

    final under15 = (probability0Goals + probability1Goal).clamp(0.0, 1.0);

    final over15 = (1.0 - under15).clamp(0.0, 1.0);

    // ==========================================================
    // OVER / UNDER 2.5
    // ==========================================================
    //
    // Under 2.5 = probabilità di 0, 1 o 2 gol.
    // ==========================================================

    final under25 = (probability0Goals + probability1Goal + probability2Goals)
        .clamp(0.0, 1.0);

    final over25 = (1.0 - under25).clamp(0.0, 1.0);

    // ==========================================================
    // GOAL / NO GOAL
    // ==========================================================
    //
    // P(entrambe segnano) =
    //
    // 1
    // - P(casa = 0)
    // - P(ospite = 0)
    // + P(entrambe = 0)
    // ==========================================================

    final homeZero = math.exp(-expectedHomeGoals);

    final awayZero = math.exp(-expectedAwayGoals);

    final bothZero = homeZero * awayZero;

    final goal = (1.0 - homeZero - awayZero + bothZero).clamp(0.0, 1.0);

    // ==========================================================
    // CONVERSIONE IN PERCENTUALI
    // ==========================================================

    var over15Percent = (over15 * 100).round();

    var under15Percent = 100 - over15Percent;

    var over25Percent = (over25 * 100).round();

    var under25Percent = 100 - over25Percent;

    var goalPercent = (goal * 100).round();

    var noGoalPercent = 100 - goalPercent;

    over15Percent = over15Percent.clamp(1, 99);

    under15Percent = under15Percent.clamp(1, 99);

    over25Percent = over25Percent.clamp(1, 99);

    under25Percent = under25Percent.clamp(1, 99);

    goalPercent = goalPercent.clamp(1, 99);

    noGoalPercent = noGoalPercent.clamp(1, 99);

    return {
      'over15': over15Percent,
      'under15': under15Percent,
      'over25': over25Percent,
      'under25': under25Percent,
      'goal': goalPercent,
      'noGoal': noGoalPercent,
    };
  }

  // ============================================================
  // EXPECTED GOALS
  // ============================================================
  //
  // Metodo utile per mostrare in futuro:
  //
  // xG stimati casa
  // xG stimati ospite
  // totale gol atteso
  // ============================================================

  static Map<String, double> calculateExpectedGoals({
    required TeamFormData homeForm,
    required TeamFormData awayForm,
  }) {
    if (homeForm.matchesPlayed <= 0 || awayForm.matchesPlayed <= 0) {
      return {'home': 0.0, 'away': 0.0, 'total': 0.0};
    }

    final homeGoalsForAverage = homeForm.goalsFor / homeForm.matchesPlayed;

    final homeGoalsAgainstAverage =
        homeForm.goalsAgainst / homeForm.matchesPlayed;

    final awayGoalsForAverage = awayForm.goalsFor / awayForm.matchesPlayed;

    final awayGoalsAgainstAverage =
        awayForm.goalsAgainst / awayForm.matchesPlayed;

    var homeExpected =
        (homeGoalsForAverage * 0.55) + (awayGoalsAgainstAverage * 0.45);

    var awayExpected =
        (awayGoalsForAverage * 0.55) + (homeGoalsAgainstAverage * 0.45);

    homeExpected *= 1.06;
    awayExpected *= 0.96;

    homeExpected = homeExpected.clamp(0.20, 3.50);

    awayExpected = awayExpected.clamp(0.15, 3.25);

    return {
      'home': homeExpected,
      'away': awayExpected,
      'total': homeExpected + awayExpected,
    };
  }

  // ============================================================
  // POISSON
  // ============================================================

  static double _poissonProbability({
    required double lambda,
    required int goals,
  }) {
    if (lambda <= 0.0 || goals < 0) {
      return 0.0;
    }

    return (math.pow(lambda, goals) * math.exp(-lambda)) / _factorial(goals);
  }

  // ============================================================
  // FATTORIALE
  // ============================================================

  static int _factorial(int value) {
    if (value <= 1) {
      return 1;
    }

    int result = 1;

    for (int i = 2; i <= value; i++) {
      result *= i;
    }

    return result;
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
