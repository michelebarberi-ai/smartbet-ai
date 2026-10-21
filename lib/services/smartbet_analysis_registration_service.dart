import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'dual_engine_analysis_service.dart';
import 'smartbet_analysis_history_store.dart';

export 'smartbet_analysis_history_store.dart' show SmartBetAnalysisSource;

class SmartBetAnalysisRegistrationService {
  final SmartBetAnalysisHistoryStore _store;

  SmartBetAnalysisRegistrationService({SmartBetAnalysisHistoryStore? store})
    : _store = store ?? SmartBetAnalysisHistoryStore.instance;

  Future<void> registerSelection({
    required MatchModel match,
    required AnalysisResult smartBet,
    required SmartBetAnalysisSource source,
    String? smartBetMarket,
    int? smartBetProbabilityPercent,
    DualEngineAnalysis? dualAnalysis,
    DateTime? recordedAt,
  }) async {
    final matchDate = DateTime.tryParse(match.date);

    if (matchDate == null || match.fixtureId <= 0) {
      return;
    }

    final comparison = dualAnalysis?.comparison;

    // ============================================================
    // SMARTBET
    // ============================================================

    final resolvedSmartBetMarket = smartBetMarket?.trim().isNotEmpty == true
        ? smartBetMarket!.trim()
        : comparison?.smartBetMarket ?? '';

    final resolvedSmartBetProbability = smartBetProbabilityPercent != null
        ? _percentToProbability(smartBetProbabilityPercent)
        : comparison?.smartBetProbability;

    if (resolvedSmartBetMarket.trim().isNotEmpty &&
        resolvedSmartBetMarket.trim().toUpperCase() != 'N/D') {
      await _store.registerAnalysis(
        engine: SmartBetAnalysisEngine.smartBet,
        source: source,
        fixtureId: match.fixtureId,
        homeTeam: match.homeTeam,
        awayTeam: match.awayTeam,
        league: match.league,
        country: match.country,
        matchDate: matchDate,
        market: resolvedSmartBetMarket,
        probability: resolvedSmartBetProbability,
        smartScore: smartBet.smartScore,
        recordedAt: recordedAt,
      );
    }

    // ============================================================
    // DIEGO
    // ============================================================
    //
    // unavailable:
    //   Diego non ha prodotto alcuna analisi -> non registriamo.
    //
    // noSelection:
    //   Diego ha prodotto una lettura statistica ma non una
    //   selezione qualificata -> la registriamo con qualified=false.
    //
    // agree / partial / diverge:
    //   Diego ha prodotto una vera selezione qualificata.
    // ============================================================

    if (dualAnalysis == null ||
        comparison == null ||
        comparison.status == DualEngineAgreement.unavailable) {
      return;
    }

    final diegoMarket = comparison.diegoMarket.trim();

    if (diegoMarket.isEmpty || diegoMarket.toUpperCase() == 'N/D') {
      return;
    }

    final qualified = comparison.status != DualEngineAgreement.noSelection;

    await _store.registerAnalysis(
      engine: SmartBetAnalysisEngine.diego,
      source: source,
      fixtureId: match.fixtureId,
      homeTeam: match.homeTeam,
      awayTeam: match.awayTeam,
      league: match.league,
      country: match.country,
      matchDate: matchDate,
      market: diegoMarket,
      probability: comparison.diegoProbability,
      confidence: comparison.diegoMarketConfidence,
      classification: comparison.diegoClassification,
      qualified: qualified,
      recordedAt: recordedAt,
    );
  }

  double _percentToProbability(int value) {
    return value.clamp(0, 100) / 100.0;
  }
}
