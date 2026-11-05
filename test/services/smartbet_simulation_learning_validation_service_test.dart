import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_learning_validation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SmartBetSimulationLearningValidationService service() =>
      SmartBetSimulationLearningValidationService(
        shadowStore: SmartBetSimulationShadowStore(),
        historyStore: SmartBetAnalysisHistoryStore(),
      );

  DateTime captureAt(int i) =>
      DateTime.utc(2026, 1, 1, 8).add(Duration(days: i));
  DateTime kickoffAt(int i) => captureAt(i).add(const Duration(hours: 12));
  DateTime resolvedAt(int i) => kickoffAt(i).add(const Duration(hours: 6));

  SmartBetSimulationShadowSnapshot snapshot(
    int i, {
    String engine = 'SMARTBET',
    double original = 0.2,
    double simulated = 0.8,
    double quality = 0.9,
    String market = 'X',
    String modelVersion = 'P21A-v1',
    DateTime? matchDate,
  }) => SmartBetSimulationShadowSnapshot(
    fixtureId: 10000 + i,
    engine: engine,
    matchDate: matchDate ?? kickoffAt(i),
    capturedAt: captureAt(i),
    modelVersion: modelVersion,
    expectedHomeGoals: 1.0,
    expectedAwayGoals: 1.0,
    dataQuality: quality,
    originalProbabilities: {market: original},
    simulatedProbabilities: {market: simulated},
    unsupportedMarkets: const [],
  );

  SmartBetAnalysisRecord outcome(
    int i, {
    bool draw = true,
    DateTime? resolved,
    DateTime? matchDate,
    bool eligible = true,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  }) => SmartBetAnalysisRecord(
    engine: engine,
    fixtureId: 10000 + i,
    homeTeam: 'Casa',
    awayTeam: 'Ospite',
    league: 'Serie A',
    country: 'Italia',
    matchDate: matchDate ?? kickoffAt(i),
    market: 'X',
    probability: 0.2,
    smartScore: 60,
    confidence: null,
    classification: null,
    qualified: null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: eligible,
    status: draw
        ? SmartBetAnalysisStatus.correct
        : SmartBetAnalysisStatus.wrong,
    actualHomeGoals: draw ? 1 : 2,
    actualAwayGoals: 1,
    firstSeenAt: captureAt(i),
    lastSeenAt: resolved ?? resolvedAt(i),
    resolvedAt: resolved ?? resolvedAt(i),
  );

  const total = 160;
  final asOf = DateTime.utc(2027, 1, 1);

  test('P21G: dati pochi => niente correzioni', () {
    final result = service().evaluate(
      snapshots: [for (var i = 0; i < 12; i++) snapshot(i)],
      history: [for (var i = 0; i < 12; i++) outcome(i)],
      asOf: asOf,
    );
    expect(
      result.markets.single.decision,
      SmartBetSimulationLearningDecision.insufficientData,
    );
    expect(result.trialCandidates, 0);
    expect(result.markets.single.eligibleCases, 12);
  });

  test('P21G: simulatore migliore su train e holdout => solo candidato', () {
    final report = service().evaluate(
      snapshots: [for (var i = 0; i < total; i++) snapshot(i)],
      history: [for (var i = 0; i < total; i++) outcome(i)],
      asOf: asOf,
    );
    final x = report.markets.single;
    expect(x.trialSuggested, isTrue);
    expect(x.candidateSimulationWeight, 1.0);
    expect(x.trainingCases, 96);
    expect(x.validationCases, 64);
    expect(x.validationImprovement, greaterThan(0));
    expect(x.firstValidationHalfImprovement, greaterThan(0));
    expect(x.secondValidationHalfImprovement, greaterThan(0));
    expect(report.toJson()['mode'], 'shadow_only');
  });

  test('P21G: buon train ma holdout peggiora => nessuna promozione', () {
    final report = service().evaluate(
      snapshots: [for (var i = 0; i < total; i++) snapshot(i)],
      history: [for (var i = 0; i < total; i++) outcome(i, draw: i < 96)],
      asOf: asOf,
    );
    final x = report.markets.single;
    expect(x.candidateSimulationWeight, 1.0);
    expect(x.decision, SmartBetSimulationLearningDecision.validationFailed);
    expect(x.validationImprovement, lessThan(0));
    expect(report.trialCandidates, 0);
  });

  test('P21G: il cervello originale gia migliore => nessun candidato', () {
    final report = service().evaluate(
      snapshots: [
        for (var i = 0; i < total; i++)
          snapshot(i, original: 0.8, simulated: 0.2),
      ],
      history: [for (var i = 0; i < total; i++) outcome(i)],
      asOf: asOf,
    );
    expect(
      report.markets.single.decision,
      SmartBetSimulationLearningDecision.noTrainingAdvantage,
    );
    expect(report.markets.single.candidateSimulationWeight, isNull);
  });

  test('P21G: apprende anche dalle partite meno affidabili', () {
    final report = service().evaluate(
      snapshots: [for (var i = 0; i < total; i++) snapshot(i, quality: 0.25)],
      history: [for (var i = 0; i < total; i++) outcome(i)],
      asOf: asOf,
    );
    expect(report.markets.single.lowQualityCases, total);
    expect(report.markets.single.trainingCases, greaterThan(0));
  });

  test('P21G: nessuna fuga dal futuro durante il training', () {
    final report = service().evaluate(
      snapshots: [for (var i = 0; i < total; i++) snapshot(i)],
      history: [
        for (var i = 0; i < total; i++)
          outcome(i, resolved: DateTime.utc(2026, 12, 1)),
      ],
      asOf: asOf,
    );
    expect(report.markets.single.trainingCases, 0);
    expect(report.markets.single.trialSuggested, isFalse);
  });

  test('P21G: risultato non ancora noto a asOf resta pending', () {
    final report = service().evaluate(
      snapshots: [snapshot(0)],
      history: [outcome(0, resolved: DateTime.utc(2027, 2, 1))],
      asOf: asOf,
    );
    expect(report.pendingSnapshots, 1);
    expect(report.markets, isEmpty);
  });

  test('P21G: risultati contraddittori esclusi', () {
    final report = service().evaluate(
      snapshots: [snapshot(0)],
      history: [outcome(0), outcome(0, draw: false)],
      asOf: asOf,
    );
    expect(report.conflictingSnapshots, 1);
    expect(report.markets, isEmpty);
  });

  test('P21G: duplicati non gonfiano il campione', () {
    final s = snapshot(0);
    final report = service().evaluate(
      snapshots: [s, s],
      history: [outcome(0)],
      asOf: asOf,
    );
    expect(report.duplicateSnapshots, 1);
    expect(report.markets.single.eligibleCases, 1);
  });

  test('P21G: snapshot con kickoff errato e mercato non supportato', () {
    final report = service().evaluate(
      snapshots: [
        snapshot(0, matchDate: kickoffAt(0).add(const Duration(days: 1))),
        snapshot(1, market: 'MERCATO SCONOSCIUTO'),
      ],
      history: [outcome(0), outcome(1)],
      asOf: asOf,
    );
    expect(report.invalidSnapshots, 1);
    expect(report.unsupportedPairs, 1);
    expect(report.markets, isEmpty);
  });

  test('P21G: SmartBet e Diego restano separati', () {
    final report = service().evaluate(
      snapshots: [
        snapshot(0, engine: 'SMARTBET'),
        snapshot(0, engine: 'DIEGO'),
      ],
      history: [outcome(0)],
      asOf: asOf,
    );
    expect(report.markets.map((m) => m.engine).toSet(), {'DIEGO', 'SMARTBET'});
    expect(report.markets.every((m) => m.eligibleCases == 1), isTrue);
  });

  test('P21G: versioni diverse del modello non vengono mescolate', () {
    final report = service().evaluate(
      snapshots: [
        snapshot(0, modelVersion: 'A'),
        snapshot(1, modelVersion: 'B'),
      ],
      history: [outcome(0), outcome(1)],
      asOf: asOf,
    );
    expect(report.markets.length, 2);
  });

  test('P21G: outcome storici non prospettici non addestrano', () {
    final report = service().evaluate(
      snapshots: [snapshot(0)],
      history: [outcome(0, eligible: false)],
      asOf: asOf,
    );
    expect(report.pendingSnapshots, 1);
    expect(report.markets, isEmpty);
  });

  test('P21G: dati reali da store, senza nuove API o scritture', () async {
    final shadows = SmartBetSimulationShadowStore();
    final history = SmartBetAnalysisHistoryStore();
    await history.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 10000,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Serie A',
      country: 'Italia',
      matchDate: kickoffAt(0),
      market: 'X',
      probability: 0.2,
      recordedAt: captureAt(0),
    );
    await shadows.saveFirst(snapshot(0));
    await history.registerActualResult(
      fixtureId: 10000,
      homeGoals: 1,
      awayGoals: 1,
      updatedAt: resolvedAt(0),
    );
    final before = shadows.snapshots.single.toJson();
    final report = await SmartBetSimulationLearningValidationService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored(asOf: asOf);
    expect(report.markets.single.eligibleCases, 1);
    expect(report.trialCandidates, 0);
    expect(shadows.snapshots.single.toJson(), before);
    expect(history.records.single.actualHomeGoals, 1);
  });
}
