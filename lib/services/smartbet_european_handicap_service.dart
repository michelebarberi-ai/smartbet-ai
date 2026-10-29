import 'dart:math' as math;

/// Probabilità dei tre esiti di un handicap europeo 1X2.
/// L'handicap viene applicato ai goal della squadra di casa.
class SmartBetEuropeanHandicapProbabilities {
  final double home;
  final double draw;
  final double away;

  const SmartBetEuropeanHandicapProbabilities({
    required this.home,
    required this.draw,
    required this.away,
  });

  double forOutcome(String outcome) {
    switch (outcome.trim().toUpperCase()) {
      case '1':
        return home;
      case 'X':
        return draw;
      case '2':
        return away;
      default:
        return 0;
    }
  }
}

class SmartBetEuropeanHandicapService {
  const SmartBetEuropeanHandicapService._();

  static SmartBetEuropeanHandicapProbabilities evaluate({
    required double expectedHomeGoals,
    required double expectedAwayGoals,
    required int homeHandicap,
  }) {
    if (!expectedHomeGoals.isFinite ||
        !expectedAwayGoals.isFinite ||
        expectedHomeGoals < 0 ||
        expectedAwayGoals < 0 ||
        expectedHomeGoals > 12 ||
        expectedAwayGoals > 12 ||
        homeHandicap < -5 ||
        homeHandicap > 5) {
      throw ArgumentError('Parametri handicap non validi');
    }

    const maxGoals = 40;
    final home = List<double>.filled(maxGoals + 1, 0);
    final away = List<double>.filled(maxGoals + 1, 0);

    home[0] = math.exp(-expectedHomeGoals);
    away[0] = math.exp(-expectedAwayGoals);

    for (var i = 1; i <= maxGoals; i++) {
      home[i] = home[i - 1] * expectedHomeGoals / i;
      away[i] = away[i - 1] * expectedAwayGoals / i;
    }

    var homeWins = 0.0;
    var draws = 0.0;
    var awayWins = 0.0;
    var total = 0.0;

    for (var h = 0; h <= maxGoals; h++) {
      for (var a = 0; a <= maxGoals; a++) {
        final mass = home[h] * away[a];
        final difference = h + homeHandicap - a;
        total += mass;

        if (difference > 0) {
          homeWins += mass;
        } else if (difference == 0) {
          draws += mass;
        } else {
          awayWins += mass;
        }
      }
    }

    if (total <= 0) {
      throw StateError('Distribuzione probabilistica non valida');
    }

    return SmartBetEuropeanHandicapProbabilities(
      home: homeWins / total,
      draw: draws / total,
      away: awayWins / total,
    );
  }
}
