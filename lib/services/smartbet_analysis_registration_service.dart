import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'dual_engine_analysis_service.dart';
import 'smartbet_analysis_comparison_store.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_shadow_learning_store.dart';
import 'smartbet_adaptive_decision_service.dart';
import 'smartbet_shadow_outcome_service.dart';
import 'smartbet_frozen_model_registration_store.dart';
import 'smartbet_simulation_shadow_capture_service.dart';
import 'smartbet_simulation_shadow_store.dart';
import 'goalvdline_central_learning_outbox.dart';

export 'smartbet_analysis_history_store.dart' show SmartBetAnalysisSource;

class SmartBetAnalysisRegistrationService {
  final SmartBetAnalysisHistoryStore _store;

  final SmartBetAnalysisComparisonStore _comparisonStore;

  final SmartBetSimulationShadowCaptureService _simulationCapture;

  final GoalVdLineCentralLearningOutbox _centralOutbox;

  SmartBetAnalysisRegistrationService({
    SmartBetAnalysisHistoryStore? store,
    SmartBetAnalysisComparisonStore? comparisonStore,
    SmartBetSimulationShadowCaptureService? simulationCapture,
    GoalVdLineCentralLearningOutbox? centralOutbox,
  }) : _store = store ?? SmartBetAnalysisHistoryStore.instance,
       _comparisonStore =
           comparisonStore ?? SmartBetAnalysisComparisonStore.instance,
       _simulationCapture =
           simulationCapture ??
           SmartBetSimulationShadowCaptureService(
             store: SmartBetSimulationShadowStore.instance,
           ),
       _centralOutbox = centralOutbox ?? GoalVdLineCentralLearningOutbox.instance;

  Future<void> registerSelection({
    required MatchModel match,
    required AnalysisResult smartBet,
    required SmartBetAnalysisSource source,
    String? smartBetMarket,
    int? smartBetProbabilityPercent,
    double? smartBetOdd,
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
        quotedOdd: smartBetOdd,
        recordedAt: recordedAt,
      );

      await _captureShadow(smartBetRecord);
      await _captureCentralDraft(smartBetRecord);

      if (smartBetRecord != null) {
        await _simulationCapture.capture(
          match: match,
          smartBet: smartBet,
          record: smartBetRecord,
          diego: dualAnalysis?.diego,
          diegoMarket: comparison?.status == DualEngineAgreement.unavailable
              ? null : comparison?.diegoMarket,
          history: _store.records,
          recordedAt: recordedAt,
        );
      }
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
      quotedOdd: qualified ? comparison.diegoOdd : null,
      recordedAt: recordedAt,
    );

    await _captureShadow(diegoRecord);
    await _captureCentralDraft(diegoRecord);

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

  Future<void> _captureCentralDraft(SmartBetAnalysisRecord? record) async {
    try {
      await _centralOutbox.captureIfEligible(record);
    } catch (error) {
      // La coda opzionale non deve mai bloccare le analisi.
      debugPrint('GoalVdLine local learning queue unavailable: $error');
    }
  }

  Future<void> _captureShadow(SmartBetAnalysisRecord? record) async {
    if (record == null) return;

    try {
      if (!record.prospectiveEligible ||
          record.status != SmartBetAnalysisStatus.pending) {
        return;
      }

      final probability = record.probability;

      if (probability == null ||
          !probability.isFinite ||
          probability < 0 ||
          probability > 1) {
        return;
      }

      final history = _store.records;
      final shadowStore = SmartBetShadowLearningStore.instance;

      await shadowStore.initialize();

      // Non rivalutare una previsione già acquisita.
      if (shadowStore.predictions.any(
        (prediction) => prediction.key == record.key,
      )) {
        return;
      }

      final outcomes = const SmartBetShadowOutcomeService().evaluate(
        history: history,
        predictions: shadowStore.predictions,
      );

      // Il servizio adattivo applica il cutoff temporale.
      final decision = const SmartBetAdaptiveDecisionService().evaluate(
        engine: record.engine,
        market: record.market,
        probability: probability,
        asOf: record.firstSeenAt,
        records: history,
        outcomes: outcomes,
        fixtureId: record.fixtureId,
      );

      // Cerca un modello shadow realmente registrato
      // prima della previsione. Nessuna attivazione live.
      SmartBetFrozenModelRegistration? selectedModel;

      try {
        final registry = SmartBetFrozenModelRegistrationStore();
        await registry.initialize();

        final eligible =
            registry.registrations
                .where(
                  (entry) =>
                      entry.model.engine == record.engine &&
                      normalizeAnalysisMarket(entry.model.market) ==
                          normalizeAnalysisMarket(record.market) &&
                      entry.model.frozenAt.toUtc().isBefore(
                        record.firstSeenAt.toUtc(),
                      ) &&
                      entry.registeredAt.toUtc().isBefore(
                        record.firstSeenAt.toUtc(),
                      ),
                )
                .toList()
              ..sort((a, b) => b.registeredAt.compareTo(a.registeredAt));

        // Se due modelli condividono la registrazione più
        // recente, non scegliamo arbitrariamente.
        if (eligible.isNotEmpty &&
            (eligible.length == 1 ||
                eligible.first.registeredAt.isAfter(
                  eligible[1].registeredAt,
                ))) {
          selectedModel = eligible.first;
        }
      } catch (error) {
        // Il registro modelli non deve bloccare lo shadow.
        debugPrint('SmartBet model binding unavailable: $error');
      }

      await shadowStore.capture(
        record: record,
        history: history,
        trialProbability: decision.trialProbability,
        trialEligible: decision.eligibleForTrial,
        decisionStatus: decision.status.name,
        registeredShadowModel: selectedModel,
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
