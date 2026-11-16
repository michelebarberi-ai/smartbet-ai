import 'dart:math' as math;

import '../models/analysis_result.dart';
import 'diego_ai_service.dart';
import 'smartbet_match_simulation_service.dart';

/// Prognosi del terzo motore: distribuzione dei punteggi Poisson bivariata.
/// Non è addestrata/calibrata e non utilizza quote bookmaker.
class GoalVdLineThirdBrainMarket {
  final String market;
  final double probability;
  final double lowerScenario;
  final double upperScenario;

  const GoalVdLineThirdBrainMarket({
    required this.market,
    required this.probability,
    required this.lowerScenario,
    required this.upperScenario,
  });
}

class GoalVdLineThirdBrainReport {
  final String inputSource;
  final int? dataConfidence;
  final double homeExpectedGoals;
  final double awayExpectedGoals;
  final bool sharesDiegoInputs;
  final List<GoalVdLineThirdBrainMarket> markets;
  final List<SmartBetSimulatedScore> likelyScores;

  const GoalVdLineThirdBrainReport({
    required this.inputSource,
    required this.dataConfidence,
    required this.homeExpectedGoals,
    required this.awayExpectedGoals,
    required this.sharesDiegoInputs,
    required this.markets,
    required this.likelyScores,
  });

  GoalVdLineThirdBrainMarket? forMarket(String market) {
    final normalized = market.toUpperCase().trim();
    for (final item in markets) {
      if (item.market == normalized) return item;
    }
    return null;
  }
}

/// Solo calcolo matematico locale: NESSUNA rete, bookmaker, modifica
/// a schedine, storico o apprendimento. La qualità dei dati è distinta
/// dalla probabilità e l'intervallo è sensibilità del modello, NON CI.
class GoalVdLineThirdBrainService {
  const GoalVdLineThirdBrainService();

  bool _usable(double home, double away) =>
      home.isFinite && away.isFinite &&
      home >= 0.10 && away >= 0.10 &&
      home <= 6.0 && away <= 6.0;

  GoalVdLineThirdBrainReport? evaluate({
    required AnalysisResult smartBet,
    DiegoAiAnalysis? diego,
  }) {
    // Preferisci xG SmartBet se l'analisi è realmente disponibile:
    // la simulazione non duplica in questo caso gli input di Diego.
    final useSmartBet = smartBet.smartScore > 0 &&
        _usable(smartBet.expectedHomeGoals, smartBet.expectedAwayGoals);
    final useDiego = diego != null &&
        _usable(diego.expectedHomeGoals, diego.expectedAwayGoals);
    if (!useSmartBet && !useDiego) return null;

    final h = useSmartBet
        ? smartBet.expectedHomeGoals : diego!.expectedHomeGoals;
    final a = useSmartBet
        ? smartBet.expectedAwayGoals : diego!.expectedAwayGoals;
    final quality = useSmartBet
        ? smartBet.dataConfidence : diego!.dataConfidence;
    // Correlazione condivisa prudente, non calibrata: scenario di prova.
    final common = math.min(0.10, math.min(h, a) * 0.10);
    final simulation = const SmartBetMatchSimulationService();
    SmartBetSimulationResult simulate(double home, double away) {
      return simulation.simulate(SmartBetMatchSimulationInput(
        expectedHomeGoals: home,
        expectedAwayGoals: away,
        sharedGoalIntensity:
            math.min(common, math.min(home, away) * 0.10),
        dataQuality: (quality / 100.0).clamp(0.0, 1.0).toDouble(),
      ));
    }

    final central = simulate(h, a);
    // Sensibilità: +/-15% sulla stima di entrambi gli attacchi.
    // Non è un intervallo statistico di confidenza.
    final lower = simulate(h * 0.85, a * 0.85);
    final upper = simulate(h * 1.15, a * 1.15);

    // Mercati ordinati solo dalle probabilità sportive calcolate.
    // Non trasformare una probabilità alta in una selezione automatica.
    final markets = <GoalVdLineThirdBrainMarket>[
      for (final entry in central.marketProbabilities.entries)
        GoalVdLineThirdBrainMarket(
          market: entry.key,
          probability: entry.value,
          lowerScenario: math.min(entry.value, math.min(
            lower.probabilityFor(entry.key), upper.probabilityFor(entry.key))),
          upperScenario: math.max(entry.value, math.max(
            lower.probabilityFor(entry.key), upper.probabilityFor(entry.key))),
        ),
    ]..sort((x, y) {
        final p = y.probability.compareTo(x.probability);
        return p != 0 ? p : x.market.compareTo(y.market);
      });
    return GoalVdLineThirdBrainReport(
      inputSource: useSmartBet ? 'SmartBet AI' : 'Diego AI',
      dataConfidence: quality > 0 ? quality : null,
      homeExpectedGoals: h,
      awayExpectedGoals: a,
      sharesDiegoInputs: !useSmartBet,
      markets: List.unmodifiable(markets),
      likelyScores: List.unmodifiable(central.topExactScores()),
    );
  }
}
