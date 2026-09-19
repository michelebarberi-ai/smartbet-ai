import 'dart:math' as math;

import '../models/analysis_result.dart';

/// Probabilità dei mercati estesi SmartBet.
///
/// Le combo vengono calcolate sulla distribuzione congiunta dei punteggi:
/// non moltiplichiamo probabilità marginali correlate.
class SmartBetMarketProbabilityService {
  const SmartBetMarketProbabilityService._();

  static const List<String> extendedMarkets = <String>[
    'OVER 3.5',
    'UNDER 3.5',
    'OVER 4.5',
    'UNDER 4.5',
    'CASA SEGNA',
    'OSPITE SEGNA',
    'CASA SEGNA PRIMA',
    'OSPITE SEGNA PRIMA',
    'CASA 2+ GOL',
    'OSPITE 2+ GOL',
    'CASA 3+ GOL',
    'OSPITE 3+ GOL',
    'GOAL + O2.5',
    'NO GOAL + U2.5',
  ];

  static int probabilityFor(AnalysisResult result, String market) {
    final key = market.trim().toUpperCase();
    final homeLambda = result.expectedHomeGoals;
    final awayLambda = result.expectedAwayGoals;

    if (homeLambda <= 0 || awayLambda <= 0) {
      return 0;
    }

    final totalLambda = homeLambda + awayLambda;
    final firstGoalMass = totalLambda <= 0 ? 0.0 : 1.0 - math.exp(-totalLambda);

    if (key == 'CASA SEGNA PRIMA') {
      final p = totalLambda <= 0
          ? 0.0
          : (homeLambda / totalLambda) * firstGoalMass;
      return (p * 100).round().clamp(0, 100);
    }

    if (key == 'OSPITE SEGNA PRIMA') {
      final p = totalLambda <= 0
          ? 0.0
          : (awayLambda / totalLambda) * firstGoalMass;
      return (p * 100).round().clamp(0, 100);
    }

    final scores = _scoreGrid(homeLambda, awayLambda);

    bool accepts(int home, int away) {
      final total = home + away;

      switch (key) {
        case 'OVER 3.5':
          return total >= 4;
        case 'UNDER 3.5':
          return total <= 3;
        case 'OVER 4.5':
          return total >= 5;
        case 'UNDER 4.5':
          return total <= 4;
        case 'CASA SEGNA':
          return home >= 1;
        case 'OSPITE SEGNA':
          return away >= 1;
        case 'CASA 2+ GOL':
          return home >= 2;
        case 'OSPITE 2+ GOL':
          return away >= 2;
        case 'CASA 3+ GOL':
          return home >= 3;
        case 'OSPITE 3+ GOL':
          return away >= 3;
        case 'MULTIGOL 1-4':
          return total >= 1 && total <= 4;
        case 'MULTIGOL 2-4':
          return total >= 2 && total <= 4;
        case 'MULTIGOL 2-5':
          return total >= 2 && total <= 5;
        case 'MULTIGOL 3-5':
          return total >= 3 && total <= 5;
        case '1X + O1.5':
          return home >= away && total >= 2;
        case 'X2 + O1.5':
          return away >= home && total >= 2;
        case '1X + U3.5':
          return home >= away && total <= 3;
        case 'X2 + U3.5':
          return away >= home && total <= 3;
        case 'GOAL + O2.5':
          return home >= 1 && away >= 1 && total >= 3;
        case 'NO GOAL + U2.5':
          return (home == 0 || away == 0) && total <= 2;
        default:
          return false;
      }
    }

    var totalMass = 0.0;
    var acceptedMass = 0.0;

    for (final score in scores) {
      totalMass += score.probability;

      if (accepts(score.home, score.away)) {
        acceptedMass += score.probability;
      }
    }

    if (totalMass <= 0) {
      return 0;
    }

    return ((acceptedMass / totalMass) * 100).round().clamp(0, 100);
  }

  static List<({int home, int away, double probability})> _scoreGrid(
    double homeLambda,
    double awayLambda,
  ) {
    const maxGoals = 10;
    final scores = <({int home, int away, double probability})>[];

    for (var home = 0; home <= maxGoals; home++) {
      final homeProbability = _poisson(homeLambda, home);

      for (var away = 0; away <= maxGoals; away++) {
        scores.add((
          home: home,
          away: away,
          probability: homeProbability * _poisson(awayLambda, away),
        ));
      }
    }

    return scores;
  }

  static double _poisson(double lambda, int goals) {
    if (lambda <= 0 || goals < 0) {
      return 0.0;
    }

    var factorial = 1;

    for (var i = 2; i <= goals; i++) {
      factorial *= i;
    }

    return math.pow(lambda, goals).toDouble() * math.exp(-lambda) / factorial;
  }
}
