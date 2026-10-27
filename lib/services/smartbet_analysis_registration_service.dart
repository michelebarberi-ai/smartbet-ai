import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'dual_engine_analysis_service.dart';
import 'smartbet_analysis_comparison_store.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_shadow_learning_store.dart';

export 'smartbet_analysis_history_store.dart' show SmartBetAnalysisSource;

class SmartBetAnalysisRegistrationService {
  final SmartBetAnalysisHistoryStore _store;

  final SmartBetAnalysisComparisonStore _comparisonStore;

  SmartBetAnalysisRegistrationService({
    SmartBetAnalysisHistoryStore? store,
    SmartBetAnalysisComparisonStore? comparisonStore,
  }) : _store = store ?? SmartBetAnalysisHistoryStore.instance,
       _comparisonStore =
           comparisonStore ?? SmartBetAnalysisComparisonStore.instance;

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

    SmartBetAnalysisRecord? smartBetRecord;

    if (resolvedSmartBetMarket.trim().isNotEmpty &&
        resolvedSmartBetMarket.trim().toUpperCase() != 'N/D') {
      smartBetRecord = await _store.registerAnalysis(
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

      await _captureShadow(smartBetRecord);
    }

    // ============================================================
    // DIEGO
    // ============================================================
    //
    // unavailable:
    //   nessuna previsione Diego -> nessun record / confronto.
    //
    // noSelection:
    //   Diego ha comunque prodotto una previsione statistica.
    //   La salviamo con qualified=false ed entra nella coppia
    //   SmartBet/Diego.
    //
    // agree / partial / diverge:
    //   previsione Diego qualificata.
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

    final diegoRecord = await _store.registerAnalysis(
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

    await _captureShadow(diegoRecord);

    // ============================================================
    // COPPIA SMARTBET ↔ DIEGO
    // ============================================================
    //
    // La coppia viene costruita usando i record realmente
    // persistiti. In questo modo:
    //
    // - dedup e normalizzazione restano una responsabilità
    //   dello HistoryStore;
    // - il ComparisonStore non deve ricostruire abbinamenti
    //   a posteriori;
    // - più mercati della stessa fixture possono mantenere
    //   coppie distinte e corrette.
    // ============================================================

    if (smartBetRecord != null && diegoRecord != null) {
      await _comparisonStore.registerPair(
        smartBet: smartBetRecord,
        diego: diegoRecord,
        source: source,
        recordedAt: recordedAt,
      );
    }
  }

  Future<void> _captureShadow(SmartBetAnalysisRecord? record) async {
    if (record == null) return;

    try {
      await SmartBetShadowLearningStore.instance.capture(
        record: record,
        history: _store.records,
      );
    } catch (error) {
      // Un problema nello shadow non blocca la registrazione.
      debugPrint('SmartBet shadow learning error: $error');
    }
  }

  double _percentToProbability(int value) {
    return value.clamp(0, 100) / 100.0;
  }
}
