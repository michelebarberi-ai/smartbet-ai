import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'diego_ai_service.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_match_simulation_service.dart';
import 'smartbet_choice_trial.dart';
import 'smartbet_simulation_bridge_service.dart';
import 'smartbet_simulation_shadow_store.dart';

/// P21C - usa soltanto risultati GIA' calcolati. Nessuna nuova API.
/// Un errore dello shadow non deve influenzare la selezione ufficiale.
class SmartBetSimulationShadowCaptureService {
  final SmartBetSimulationShadowStore store;
  final SmartBetSimulationBridgeService bridge;

  const SmartBetSimulationShadowCaptureService({
    required this.store,
    this.bridge = const SmartBetSimulationBridgeService(),
  });

  Future<void> capture({
    required MatchModel match,
    required AnalysisResult smartBet,
    required SmartBetAnalysisRecord record,
    DiegoAiAnalysis? diego,
    String? diegoMarket,
    Iterable<SmartBetAnalysisRecord> history = const [],
    DateTime? recordedAt,
  }) async {
    try {
      final capturedAt = (recordedAt ?? DateTime.now()).toUtc();
      final kickoff = record.matchDate.toUtc();
      if (record.fixtureId != match.fixtureId ||
          !record.prospectiveEligible ||
          !capturedAt.isBefore(kickoff) ||
          record.status != SmartBetAnalysisStatus.pending) {
        return;
      }

      // Gli xG a zero sono sentinella di dato mancante in AnalysisResult.
      if (record.engine == SmartBetAnalysisEngine.smartBet &&
          _validGoals(smartBet.expectedHomeGoals, smartBet.expectedAwayGoals)) {
        final report = bridge.fromSmartBet(
          result: smartBet,
          fixtureId: match.fixtureId.toString(),
          dataQuality: (smartBet.dataConfidence.clamp(0, 100)) / 100.0,
        );
        await store.saveFirst(
          _snapshot(
            official: record.market,
            engine: SmartBetAnalysisEngine.smartBet,
            history: history,
            historyObservedNow: recordedAt == null,
            report: report,
            fixtureId: match.fixtureId,
            matchDate: kickoff,
            capturedAt: capturedAt,
          ),
        );
      }

      // Confronto Diego solo quando il risultato nativo e' gia' in memoria.
      // La sola DualEngineComparison non contiene il Match Engine di Diego.
      if (diego != null &&
          diego.match.fixtureId == match.fixtureId &&
          _validGoals(diego.expectedHomeGoals, diego.expectedAwayGoals)) {
        final report = bridge.fromDiego(
          result: diego.engine,
          fixtureId: match.fixtureId.toString(),
          dataQuality: (diego.dataConfidence.clamp(0, 100)) / 100.0,
        );
        await store.saveFirst(
          _snapshot(
            official: diegoMarket ?? '',
            engine: SmartBetAnalysisEngine.diego,
            history: history,
            historyObservedNow: recordedAt == null,
            report: report,
            fixtureId: match.fixtureId,
            matchDate: kickoff,
            capturedAt: capturedAt,
          ),
        );
      }
    } catch (error) {
      debugPrint('SmartBet P21C shadow capture unavailable: $error');
    }
  }

  static bool _validGoals(double home, double away) =>
      home.isFinite &&
      away.isFinite &&
      home > 0 &&
      away > 0 &&
      home <= 6 &&
      away <= 6;

  static SmartBetSimulationShadowSnapshot _snapshot({
    required String official,
    required SmartBetAnalysisEngine engine,
    required Iterable<SmartBetAnalysisRecord> history,
    required bool historyObservedNow,
    required SmartBetSimulationComparisonReport report,
    required int fixtureId,
    required DateTime matchDate,
    required DateTime capturedAt,
  }) {
    final original = {for (final d in report.comparedMarkets) d.market: d.existingProbability};
    final simulated = {for (final d in report.comparedMarkets) d.market: d.simulatedProbability};
    final market = normalizeAnalysisMarket(official);
    final trial = SmartBetChoiceTrial.choose(
      official: market, original: original, simulated: simulated,
      fixtureId: fixtureId, engine: engine, history: history,
      cutoff: capturedAt, historyObservedNow: historyObservedNow,
    );
    return SmartBetSimulationShadowSnapshot(
      officialChoice: trial == null ? null : market,
      trialChoiceV1: trial,
      fixtureId: fixtureId,
      engine: report.source,
      matchDate: matchDate,
      capturedAt: capturedAt,
      modelVersion: SmartBetMatchSimulationService.modelVersion,
      expectedHomeGoals: report.simulation.input.expectedHomeGoals,
      expectedAwayGoals: report.simulation.input.expectedAwayGoals,
      dataQuality: report.dataQuality,
      originalProbabilities: original,
      simulatedProbabilities: simulated,
      unsupportedMarkets: report.unsupportedMarkets,
    );
  }
}
