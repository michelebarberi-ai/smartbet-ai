import 'dart:math' as math;

import '../models/goalvdline_match_engine_models.dart';

class DiegoAiMarketProbability {
  final String market;

  /// Probabilità interna 0.0 - 1.0.
  final double probability;

  const DiegoAiMarketProbability({
    required this.market,
    required this.probability,
  });

  double get percent => probability * 100.0;
}

/// Costruisce il catalogo dei mercati DiegoAI partendo
/// esclusivamente dalla distribuzione del Match Engine.
///
/// I mercati già prodotti direttamente dal motore mantengono
/// le rispettive probabilità native.
///
/// I mercati estesi vengono derivati dagli expected goals
/// prodotti da DiegoAI tramite distribuzione di Poisson.
///
/// Nessuna quota bookmaker entra nel calcolo delle probabilità.
class DiegoAiMarketProbabilityService {
  const DiegoAiMarketProbabilityService();

  List<DiegoAiMarketProbability> build(GoalVdLineMatchEngineResult result) {
    final home = result.homeWinProbability;
    final draw = result.drawProbability;
    final away = result.awayWinProbability;

    final homeLambda = result.expectedHomeGoals;
    final awayLambda = result.expectedAwayGoals;
    final totalLambda = homeLambda + awayLambda;

    final scores = _scoreGrid(homeLambda, awayLambda);

    double scoreProbability(bool Function(int home, int away) accepts) {
      if (scores.isEmpty) return 0.0;

      var totalMass = 0.0;
      var acceptedMass = 0.0;

      for (final score in scores) {
        totalMass += score.probability;

        if (accepts(score.home, score.away)) {
          acceptedMass += score.probability;
        }
      }

      if (totalMass <= 0) return 0.0;

      return (acceptedMass / totalMass).clamp(0.0, 1.0).toDouble();
    }

    final firstGoalMass = totalLambda > 0 ? 1.0 - math.exp(-totalLambda) : 0.0;

    final homeScoresFirst = totalLambda > 0
        ? (homeLambda / totalLambda) * firstGoalMass
        : 0.0;

    final awayScoresFirst = totalLambda > 0
        ? (awayLambda / totalLambda) * firstGoalMass
        : 0.0;

    final markets = <DiegoAiMarketProbability>[
      // ========================================================
      // 1X2
      // ========================================================

      DiegoAiMarketProbability(market: '1', probability: home),
      DiegoAiMarketProbability(market: 'X', probability: draw),
      DiegoAiMarketProbability(market: '2', probability: away),

      // ========================================================
      // DOPPIA CHANCE
      // ========================================================
      DiegoAiMarketProbability(market: '1X', probability: home + draw),
      DiegoAiMarketProbability(market: 'X2', probability: draw + away),
      DiegoAiMarketProbability(market: '12', probability: home + away),

      // ========================================================
      // OVER / UNDER NATIVI
      // ========================================================
      DiegoAiMarketProbability(
        market: 'OVER 1.5',
        probability: result.over15Probability,
      ),
      DiegoAiMarketProbability(
        market: 'UNDER 1.5',
        probability: result.under15Probability,
      ),
      DiegoAiMarketProbability(
        market: 'OVER 2.5',
        probability: result.over25Probability,
      ),
      DiegoAiMarketProbability(
        market: 'UNDER 2.5',
        probability: result.under25Probability,
      ),
      DiegoAiMarketProbability(
        market: 'OVER 3.5',
        probability: result.over35Probability,
      ),
      DiegoAiMarketProbability(
        market: 'UNDER 3.5',
        probability: result.under35Probability,
      ),

      // ========================================================
      // OVER / UNDER ESTESO
      // ========================================================
      DiegoAiMarketProbability(
        market: 'OVER 4.5',
        probability: scoreProbability((h, a) => h + a >= 5),
      ),
      DiegoAiMarketProbability(
        market: 'UNDER 4.5',
        probability: scoreProbability((h, a) => h + a <= 4),
      ),

      // ========================================================
      // BOTH TEAMS TO SCORE
      // ========================================================
      DiegoAiMarketProbability(
        market: 'GOAL',
        probability: result.goalProbability,
      ),
      DiegoAiMarketProbability(
        market: 'NO GOAL',
        probability: result.noGoalProbability,
      ),

      // ========================================================
      // SQUADRA SEGNA
      // ========================================================
      DiegoAiMarketProbability(
        market: 'CASA SEGNA',
        probability: scoreProbability((h, a) => h >= 1),
      ),
      DiegoAiMarketProbability(
        market: 'OSPITE SEGNA',
        probability: scoreProbability((h, a) => a >= 1),
      ),

      DiegoAiMarketProbability(
        market: 'CASA SEGNA PRIMA',
        probability: homeScoresFirst,
      ),
      DiegoAiMarketProbability(
        market: 'OSPITE SEGNA PRIMA',
        probability: awayScoresFirst,
      ),

      DiegoAiMarketProbability(
        market: 'CASA 2+ GOL',
        probability: scoreProbability((h, a) => h >= 2),
      ),
      DiegoAiMarketProbability(
        market: 'OSPITE 2+ GOL',
        probability: scoreProbability((h, a) => a >= 2),
      ),
      DiegoAiMarketProbability(
        market: 'CASA 3+ GOL',
        probability: scoreProbability((h, a) => h >= 3),
      ),
      DiegoAiMarketProbability(
        market: 'OSPITE 3+ GOL',
        probability: scoreProbability((h, a) => a >= 3),
      ),

      // ========================================================
      // COMBO
      // ========================================================
      DiegoAiMarketProbability(
        market: 'GOAL + O2.5',
        probability: scoreProbability((h, a) => h >= 1 && a >= 1 && h + a >= 3),
      ),
      DiegoAiMarketProbability(
        market: 'NO GOAL + U2.5',
        probability: scoreProbability(
          (h, a) => (h == 0 || a == 0) && h + a <= 2,
        ),
      ),
    ];

    return List.unmodifiable(markets);
  }

  Map<String, double> asMap(GoalVdLineMatchEngineResult result) {
    return Map.unmodifiable({
      for (final item in build(result)) item.market: item.probability,
    });
  }

  DiegoAiMarketProbability? probabilityFor({
    required GoalVdLineMatchEngineResult result,
    required String market,
  }) {
    final wanted = _normalize(market);

    for (final item in build(result)) {
      if (_normalize(item.market) == wanted) {
        return item;
      }
    }

    return null;
  }

  List<DiegoAiMarketProbability> ranked(GoalVdLineMatchEngineResult result) {
    final list = build(result).toList()
      ..sort((a, b) => b.probability.compareTo(a.probability));

    return List.unmodifiable(list);
  }

  List<({int home, int away, double probability})> _scoreGrid(
    double homeLambda,
    double awayLambda,
  ) {
    if (homeLambda <= 0 || awayLambda <= 0) {
      return const [];
    }

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

  double _poisson(double lambda, int goals) {
    if (lambda <= 0 || goals < 0) {
      return 0.0;
    }

    var factorial = 1;

    for (var i = 2; i <= goals; i++) {
      factorial *= i;
    }

    return math.pow(lambda, goals).toDouble() * math.exp(-lambda) / factorial;
  }

  String _normalize(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
