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
/// Nessuna quota bookmaker entra in questo calcolo.
class DiegoAiMarketProbabilityService {
  const DiegoAiMarketProbabilityService();

  List<DiegoAiMarketProbability> build(GoalVdLineMatchEngineResult result) {
    final home = result.homeWinProbability;
    final draw = result.drawProbability;
    final away = result.awayWinProbability;

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
      //
      // Queste probabilità derivano direttamente dagli stessi
      // scenari 1X2 e quindi mantengono coerenza matematica.
      // ========================================================
      DiegoAiMarketProbability(market: '1X', probability: home + draw),
      DiegoAiMarketProbability(market: 'X2', probability: draw + away),
      DiegoAiMarketProbability(market: '12', probability: home + away),

      // ========================================================
      // OVER / UNDER
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

  String _normalize(String value) {
    return value.trim().toUpperCase();
  }
}
