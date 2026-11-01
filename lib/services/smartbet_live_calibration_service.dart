import 'smartbet_adaptive_decision_service.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_historical_calibration_service.dart';
import 'smartbet_learning_gate_service.dart';
import 'smartbet_shadow_learning_store.dart';
import 'smartbet_shadow_outcome_service.dart';

/// Risultato esplicito: la probabilità originale rimane disponibile
/// per lo storico e per il confronto prospettico.
class SmartBetLiveCalibrationResult {
  final int originalPercent;
  final int percent;
  final int historicalSamples;
  final bool applied;

  const SmartBetLiveCalibrationResult({
    required this.originalPercent,
    required this.percent,
    required this.historicalSamples,
    required this.applied,
  });
}

/// Snapshot immutabile creato all'inizio di una singola generazione.
/// Non usa mai risultati risolti dopo startedAt e non modifica lo storico.
class SmartBetLiveCalibrationSession {
  final bool enabled;
  final bool emergencyStop;
  final DateTime startedAt;
  final List<SmartBetAnalysisRecord> history;
  final SmartBetLearningGateReport gate;

  const SmartBetLiveCalibrationSession({
    required this.enabled,
    required this.emergencyStop,
    required this.startedAt,
    required this.history,
    required this.gate,
  });

  int get eligibleMarkets => gate.decisions
      .where(
        (decision) =>
            decision.engine == SmartBetAnalysisEngine.smartBet.name &&
            decision.eligibleForTrial,
      )
      .length;

  SmartBetLiveCalibrationResult evaluate({
    required String market,
    required int originalPercent,
    required int fixtureId,
  }) {
    final unchanged = SmartBetLiveCalibrationResult(
      originalPercent: originalPercent,
      percent: originalPercent,
      historicalSamples: 0,
      applied: false,
    );

    // Fail closed. Il consenso non è sufficiente: serve il gate prospettico.
    if (!enabled ||
        emergencyStop ||
        eligibleMarkets == 0 ||
        originalPercent < 0 ||
        originalPercent > 100 ||
        fixtureId <= 0) {
      return unchanged;
    }

    try {
      final normalized = normalizeAnalysisMarket(market);
      final allowed = gate.decisions.where(
        (decision) =>
            decision.engine == SmartBetAnalysisEngine.smartBet.name &&
            decision.market == normalized &&
            decision.eligibleForTrial,
      );
      if (allowed.length != 1) return unchanged;

      final calibration = const SmartBetHistoricalCalibrationService().evaluate(
        engine: SmartBetAnalysisEngine.smartBet,
        market: market,
        probability: originalPercent / 100.0,
        asOf: startedAt,
        records: history,
        fixtureId: fixtureId,
      );
      final decision = const SmartBetAdaptiveDecisionService().decide(
        engine: SmartBetAnalysisEngine.smartBet,
        market: market,
        calibration: calibration,
        gate: gate,
      );
      if (!decision.eligibleForTrial) return unchanged;

      // La calibrazione esistente limita a +/- 10 punti percentuali.
      // Ribadiamo il limite anche dopo l'arrotondamento ad interi.
      final rounded = (decision.trialProbability * 100).round();
      final percent = rounded
          .clamp(
            (originalPercent - 10).clamp(0, 100),
            (originalPercent + 10).clamp(0, 100),
          )
          .toInt();
      if (percent == originalPercent) return unchanged;

      return SmartBetLiveCalibrationResult(
        originalPercent: originalPercent,
        percent: percent,
        historicalSamples: decision.trainingSamples,
        applied: true,
      );
    } catch (_) {
      // Un dato corrotto o un errore di apprendimento NON deve influenzare la schedina.
      return unchanged;
    }
  }
}

/// Carica una sola volta i dati già disponibili sul dispositivo.
/// Nessuna chiamata AI e nessuna scrittura nello storico.
class SmartBetLiveCalibrationService {
  const SmartBetLiveCalibrationService();

  Future<SmartBetLiveCalibrationSession> prepare({
    required bool optedIn,
    bool emergencyStop = false,
    DateTime? startedAt,
  }) async {
    final cutoff = (startedAt ?? DateTime.now()).toUtc();
    if (!optedIn || emergencyStop) {
      return SmartBetLiveCalibrationSession(
        enabled: false,
        emergencyStop: emergencyStop,
        startedAt: cutoff,
        history: const [],
        gate: const SmartBetLearningGateReport(decisions: []),
      );
    }

    final historyStore = SmartBetAnalysisHistoryStore.instance;
    final shadowStore = SmartBetShadowLearningStore.instance;
    await Future.wait([historyStore.initialize(), shadowStore.initialize()]);

    final history = List<SmartBetAnalysisRecord>.unmodifiable(
      historyStore.records,
    );
    final predictions = List<SmartBetShadowPrediction>.unmodifiable(
      shadowStore.predictions,
    );
    final outcomes = const SmartBetShadowOutcomeService().evaluate(
      history: history,
      predictions: predictions,
    );
    final gate = const SmartBetLearningGateService().evaluate(
      outcomes,
      asOf: cutoff,
    );

    return SmartBetLiveCalibrationSession(
      enabled: true,
      emergencyStop: false,
      startedAt: cutoff,
      history: history,
      gate: gate,
    );
  }
}
