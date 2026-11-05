import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_outcome_audit_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final kickoff = DateTime.utc(2026, 11, 10, 20);
  final before = DateTime.utc(2026, 11, 10, 10);
  final after = DateTime.utc(2026, 11, 11, 10);

  SmartBetSimulationShadowSnapshot snapshot(
    int fixtureId, {
    String engine = 'SMARTBET',
    DateTime? matchDate,
    Map<String, double>? original,
    Map<String, double>? simulated,
  }) => SmartBetSimulationShadowSnapshot(
    fixtureId: fixtureId,
    engine: engine,
    matchDate: matchDate ?? kickoff,
    capturedAt: before,
    modelVersion: 'P21A-test',
    expectedHomeGoals: 1.2,
    expectedAwayGoals: 1.1,
    dataQuality: 0.9,
    originalProbabilities: original ?? {'X': 0.25, 'OVER 2.5': 0.60},
    simulatedProbabilities: simulated ?? {'X': 0.40, 'OVER 2.5': 0.30},
    unsupportedMarkets: const [],
  );

  SmartBetAnalysisRecord result(
    int fixtureId, {
    int home = 1,
    int away = 1,
    String market = 'X',
    DateTime? matchDate,
    DateTime? resolvedAt,
  }) => SmartBetAnalysisRecord(
    engine: SmartBetAnalysisEngine.smartBet,
    fixtureId: fixtureId,
    homeTeam: 'Casa',
    awayTeam: 'Ospite',
    league: 'Serie A',
    country: 'Italia',
    matchDate: matchDate ?? kickoff,
    market: market,
    probability: 0.25,
    smartScore: 65,
    confidence: null,
    classification: null,
    qualified: null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: true,
    status: SmartBetAnalysisStatus.correct,
    actualHomeGoals: home,
    actualAwayGoals: away,
    firstSeenAt: before,
    lastSeenAt: before,
    resolvedAt: resolvedAt ?? after,
  );

  final auditor = SmartBetSimulationOutcomeAuditService();

  test('P21D: stesso evento, Brier per X e Over 2.5', () {
    final report = auditor.evaluate(
      snapshots: [snapshot(2001)],
      history: [result(2001)],
    );
    expect(report.snapshotCount, 1);
    expect(report.comparedSnapshots, 1);
    expect(report.comparedMarketPairs, 2);
    final draw = report.metricFor(engine: 'SMARTBET', market: 'X')!;
    expect(draw.sampleSize, 1);
    expect(draw.observedFrequency, 1);
    expect(draw.originalBrier, closeTo(0.5625, 1e-12));
    expect(draw.simulatedBrier, closeTo(0.36, 1e-12));
    expect(draw.brierImprovement, closeTo(0.2025, 1e-12));
    expect(draw.exploratoryOnly, isTrue);
    final over = report.metricFor(engine: 'SMARTBET', market: 'OVER 2.5')!;
    expect(over.observedFrequency, 0);
    expect(over.originalBrier, closeTo(0.36, 1e-12));
    expect(over.simulatedBrier, closeTo(0.09, 1e-12));
  });

  test('P21D: due motori sulla stessa partita, stesso risultato', () {
    final report = auditor.evaluate(
      snapshots: [
        snapshot(2002),
        snapshot(2002, engine: 'DIEGO'),
      ],
      history: [result(2002)],
    );
    expect(report.comparedSnapshots, 2);
    expect(report.comparedMarketPairs, 4);
    expect(report.metricFor(engine: 'SMARTBET', market: 'X')!.sampleSize, 1);
    expect(report.metricFor(engine: 'DIEGO', market: 'X')!.sampleSize, 1);
  });

  test('P21D: partita non risolta resta pending, nessun dato inventato', () {
    final report = auditor.evaluate(
      snapshots: [snapshot(2003)],
      history: const [],
    );
    expect(report.pendingSnapshots, 1);
    expect(report.comparedMarketPairs, 0);
    expect(report.metrics, isEmpty);
  });

  test('P21D: risultati contrastanti della stessa fixture vengono esclusi', () {
    final report = auditor.evaluate(
      snapshots: [snapshot(2004)],
      history: [
        result(2004),
        result(2004, home: 2, away: 1, market: '1'),
      ],
    );
    expect(report.conflictingFixtures, 1);
    expect(report.comparedMarketPairs, 0);
  });

  test('P21D: date non corrispondenti escluse e duplicati non ricontati', () {
    final report = auditor.evaluate(
      snapshots: [
        snapshot(2005, matchDate: kickoff.add(const Duration(days: 1))),
        snapshot(2005),
      ],
      history: [result(2005)],
    );
    expect(report.invalidFixtureSnapshots, 1);
    expect(report.duplicateSnapshots, 1);
    expect(report.comparedMarketPairs, 0);
  });

  test('P21D: mercati diversi non appaiati, sconosciuti ignorati', () {
    final report = auditor.evaluate(
      snapshots: [
        snapshot(
          2006,
          original: {'X': 0.3, 'GOAL': 0.55, 'MERCATO MISTERIOSO': 0.8},
          simulated: {'X': 0.35, 'OVER 2.5': 0.6, 'MERCATO MISTERIOSO': 0.8},
        ),
      ],
      history: [result(2006)],
    );
    expect(report.comparedMarketPairs, 1);
    expect(report.unmatchedMarketPairs, 2);
    expect(report.unsupportedMarketPairs, 1);
  });

  test('P21D: peggioramento Brier negativo, niente autovalidazione', () {
    final report = auditor.evaluate(
      snapshots: [
        snapshot(2007, original: {'X': 0.9}, simulated: {'X': 0.1}),
      ],
      history: [result(2007)],
    );
    final metric = report.metricFor(engine: 'SMARTBET', market: 'X')!;
    expect(metric.brierImprovement, lessThan(0));
    expect(metric.exploratoryOnly, isTrue);
    expect(report.toJson()['schema'], 'smartbet_p21d_outcome_audit_v1');
  });

  test('P21D: nessuna dipendenza dalle quote o da mercati selezionati', () {
    final report = auditor.evaluate(
      snapshots: [snapshot(2008)],
      history: [result(2008, market: '1')],
    );
    expect(report.metricFor(engine: 'SMARTBET', market: 'X'), isNotNull);
    expect(report.metricFor(engine: 'SMARTBET', market: 'OVER 2.5'), isNotNull);
  });

  test('P21D: lettura da store persistenti, senza chiamate API', () async {
    final history = SmartBetAnalysisHistoryStore();
    final shadows = SmartBetSimulationShadowStore();
    await history.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 2009,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Serie A',
      country: 'Italia',
      matchDate: kickoff,
      market: 'X',
      probability: 0.25,
      recordedAt: before,
    );
    await shadows.saveFirst(snapshot(2009));
    final count = await history.registerActualResult(
      fixtureId: 2009,
      homeGoals: 1,
      awayGoals: 1,
      updatedAt: after,
    );
    expect(count, 1);
    final report = await SmartBetSimulationOutcomeAuditService(
      shadowStore: shadows,
      historyStore: history,
    ).evaluateStored();
    expect(report.comparedMarketPairs, 2);
    expect(report.pendingSnapshots, 0);
    expect(history.records.single.actualHomeGoals, 1);
    expect(shadows.snapshots.single.originalProbabilities['X'], 0.25);
  });
}
