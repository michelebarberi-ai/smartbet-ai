import '../models/analysis_result.dart';
import 'goalvdline_reliable_alternative_market_service.dart';
import 'smartbet_match_simulation_service.dart';

/// Collega soltanto SmartCore alla fase SHADOW dei mercati alternativi.
/// Non usa backend, bookmaker, altri motori, cache condivise o stake.
/// La qualita non misurata (dataConfidence == 0) resta sconosciuta:
/// NON viene ricavata dallo SmartScore, che ha un altro significato.
class GoalVdLineSmartCoreAlternativePreviewService {
  const GoalVdLineSmartCoreAlternativePreviewService();

  GoalVdLineAlternativeMarketPlan? build(AnalysisResult smartCore) {
    final home = smartCore.expectedHomeGoals;
    final away = smartCore.expectedAwayGoals;
    if (smartCore.smartScore <= 0 ||
        smartCore.prediction.trim().isEmpty ||
        !home.isFinite ||
        !away.isFinite ||
        home <= 0 ||
        away <= 0 ||
        home > 6 ||
        away > 6) {
      return null;
    }

    // Il calcolo alternativo rimane separato dal pronostico SmartCore,
    // compreso quando i due metodi differiscono sullo stesso esito.
    final simulation = const SmartBetMatchSimulationService().simulate(
      SmartBetMatchSimulationInput(
        expectedHomeGoals: home,
        expectedAwayGoals: away,
        dataQuality: (smartCore.dataConfidence.clamp(0, 100) / 100).toDouble(),
      ),
    );

    // Nessuna quota per questo adattatore: lo scopo è osservare
    // i mercati possibili, non alterare schedine o pronostici.
    return const GoalVdLineReliableAlternativeMarketService().evaluate(
      engineId: 'SmartCore',
      primaryMarket: smartCore.prediction,
      simulation: simulation,
    );
  }
}
