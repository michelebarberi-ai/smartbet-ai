import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_match_simulation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_learning_validation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_outcome_audit_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_store.dart';

/// P21I: controllo di integrazione dal modello fino alla verifica degli esiti.
/// Dati completamente sintetici, senza rete, quote o modifiche di produzione.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final captured = DateTime.utc(2026, 8, 10, 9);
  final kickoff = DateTime.utc(2026, 8, 10, 20);
  final resolved = DateTime.utc(2026, 8, 11, 8);
  final future = DateTime.utc(2026, 8, 12, 8);

  SmartBetSimulationShadowSnapshot snapshot({
    required int fixtureId,
    String engine = 'SMARTBET',
    double quality = 0.85,
    double originalX = 0.20,
    DateTime? capturedAt,
  }) {
    final result = const SmartBetMatchSimulationService().simulate(
      SmartBetMatchSimulationInput(
        expectedHomeGoals: 1.1,
        expectedAwayGoals: 1.0,
        dataQuality: quality,
      ),
    );
    return SmartBetSimulationShadowSnapshot(
      fixtureId: fixtureId,
      engine: engine,
      matchDate: kickoff,
      capturedAt: capturedAt ?? captured,
      modelVersion: SmartBetMatchSimulationService.modelVersion,
      expectedHomeGoals: result.input.expectedHomeGoals,
      expectedAwayGoals: result.input.expectedAwayGoals,
      dataQuality: quality,
      originalProbabilities: {'X': originalX, 'GOAL': 0.52, 'OVER 2.5': 0.55},
      simulatedProbabilities: {
        'X': result.draw,
        'GOAL': result.probabilityFor('GOAL'),
        'OVER 2.5': result.probabilityFor('OVER 2.5'),
      },
      unsupportedMarkets: const [],
    );
  }

  Future<void> register(
    SmartBetAnalysisHistoryStore history,
    int fixtureId, {
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    DateTime? recordedAt,
    double probability = 0.20,
  }) async {
    final record = await history.registerAnalysis(
      engine: engine,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: fixtureId,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Campionato test',
      country: 'Italia',
      matchDate: kickoff,
      market: 'X',
      probability: probability,
      recordedAt: recordedAt ?? captured,
    );
    expect(record, isNotNull);
  }

  test('P21I: simulazione -> snapshot -> finale -> Brier e learning', () async {
    final shadows = SmartBetSimulationShadowStore();
    final history = SmartBetAnalysisHistoryStore();
    await register(history, 21001);
    final before = snapshot(fixtureId: 21001);
    expect(await shadows.saveFirst(before), isTrue);
    expect(shadows.snapshots.single.originalProbabilities['X'], 0.20);
    expect(
      shadows.snapshots.single.simulatedProbabilities['X'],
      closeTo(before.simulatedProbabilities['X']!, 1e-12),
    );

    final updated = await history.registerActualResult(
      fixtureId: 21001,
      homeGoals: 1,
      awayGoals: 1,
      updatedAt: resolved,
    );
    expect(updated, 1);

    final audit = await SmartBetSimulationOutcomeAuditService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored();
    expect(audit.comparedSnapshots, 1);
    expect(audit.comparedMarketPairs, 3);
    expect(
      audit.metricFor(engine: 'SMARTBET', market: 'X')!.observedFrequency,
      1,
    );
    expect(audit.metricFor(engine: 'SMARTBET', market: 'GOAL'), isNotNull);
    expect(audit.metricFor(engine: 'SMARTBET', market: 'OVER 2.5'), isNotNull);

    final learn = await SmartBetSimulationLearningValidationService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored(asOf: future);
    expect(learn.totalSnapshots, 1);
    expect(learn.markets.map((m) => m.market).toSet(), {
      'X',
      'GOAL',
      'OVER 2.5',
    });
    expect(learn.trialCandidates, 0);
    expect(
      learn.markets.every(
        (m) =>
            m.decision == SmartBetSimulationLearningDecision.insufficientData,
      ),
      isTrue,
    );
    expect(shadows.snapshots.single.toJson(), before.toJson());
  });

  test('P21I: la seconda analisi non riscrive la prima previsione', () async {
    final shadows = SmartBetSimulationShadowStore();
    final history = SmartBetAnalysisHistoryStore();
    await register(history, 21002);
    final first = snapshot(fixtureId: 21002, originalX: 0.22);
    expect(await shadows.saveFirst(first), isTrue);
    await register(history, 21002, probability: 0.92);
    expect(
      await shadows.saveFirst(snapshot(fixtureId: 21002, originalX: 0.92)),
      isFalse,
    );
    expect(history.records.length, 1);
    expect(history.records.single.probability, closeTo(0.20, 1e-10));
    expect(shadows.snapshots.length, 1);
    expect(shadows.snapshots.single.originalProbabilities['X'], 0.22);
  });

  test(
    'P21I: prima del risultato non esiste alcuna prova di accuratezza',
    () async {
      final shadows = SmartBetSimulationShadowStore();
      final history = SmartBetAnalysisHistoryStore();
      await register(history, 21003);
      await shadows.saveFirst(snapshot(fixtureId: 21003));

      final audit = await SmartBetSimulationOutcomeAuditService(
        shadowStore: shadows,
        historyStore: history,
      ).evaluateStored();
      expect(audit.comparedMarketPairs, 0);
      expect(audit.pendingSnapshots, 1);

      final learn = await SmartBetSimulationLearningValidationService(
        shadowStore: shadows,
        historyStore: history,
      ).evaluateStored(asOf: future);
      expect(learn.markets, isEmpty);
      expect(learn.trialCandidates, 0);
    },
  );

  test('P21I: i risultati futuri non contaminano il confronto asOf', () async {
    final shadows = SmartBetSimulationShadowStore();
    final history = SmartBetAnalysisHistoryStore();
    await register(history, 21004);
    await shadows.saveFirst(snapshot(fixtureId: 21004));
    await history.registerActualResult(
      fixtureId: 21004,
      homeGoals: 0,
      awayGoals: 0,
      updatedAt: DateTime.utc(2026, 8, 20, 9),
    );
    final learn = await SmartBetSimulationLearningValidationService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored(asOf: future);
    expect(learn.pendingSnapshots, 1);
    expect(learn.markets, isEmpty);
  });

  test('P21I: SmartBet e Diego rimangono due confronti distinti', () async {
    final shadows = SmartBetSimulationShadowStore();
    final history = SmartBetAnalysisHistoryStore();
    await register(history, 21005);
    await shadows.saveFirst(snapshot(fixtureId: 21005));
    await shadows.saveFirst(snapshot(fixtureId: 21005, engine: 'DIEGO'));
    await history.registerActualResult(
      fixtureId: 21005,
      homeGoals: 1,
      awayGoals: 1,
      updatedAt: resolved,
    );
    final audit = await SmartBetSimulationOutcomeAuditService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored();
    expect(audit.comparedMarketPairs, 6);
    expect(audit.metricFor(engine: 'SMARTBET', market: 'X')!.sampleSize, 1);
    expect(audit.metricFor(engine: 'DIEGO', market: 'X')!.sampleSize, 1);
    final learn = await SmartBetSimulationLearningValidationService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored(asOf: future);
    expect(learn.markets.map((m) => m.engine).toSet(), {'SMARTBET', 'DIEGO'});
  });

  test('P21I: qualita bassa non cancella le partite dal learning', () async {
    final shadows = SmartBetSimulationShadowStore();
    final history = SmartBetAnalysisHistoryStore();
    await register(history, 21006);
    await shadows.saveFirst(snapshot(fixtureId: 21006, quality: 0.2));
    await history.registerActualResult(
      fixtureId: 21006,
      homeGoals: 2,
      awayGoals: 1,
      updatedAt: resolved,
    );
    final learn = await SmartBetSimulationLearningValidationService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored(asOf: future);
    expect(learn.markets.length, 3);
    expect(learn.markets.every((m) => m.lowQualityCases == 1), isTrue);
    expect(learn.trialCandidates, 0);
  });
}
