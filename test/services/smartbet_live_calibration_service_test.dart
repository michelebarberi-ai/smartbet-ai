import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_learning_gate_service.dart';
import 'package:smartbet_ai_new/services/smartbet_live_calibration_service.dart';

void main() {
  final cutoff = DateTime.utc(2026, 11, 1, 14);

  SmartBetAnalysisRecord record(
    int fixtureId, {
    bool correct = false,
    DateTime? resolvedAt,
    String market = 'GOAL',
  }) => SmartBetAnalysisRecord(
    engine: SmartBetAnalysisEngine.smartBet,
    fixtureId: fixtureId,
    homeTeam: 'Casa',
    awayTeam: 'Ospite',
    league: 'Serie A',
    country: 'Italia',
    matchDate: DateTime.utc(2026, 10, 20),
    market: market,
    probability: 0.80,
    smartScore: 75,
    confidence: null,
    classification: null,
    qualified: null,
    sources: const [SmartBetAnalysisSource.aiCoupon],
    prospectiveEligible: true,
    status: correct
        ? SmartBetAnalysisStatus.correct
        : SmartBetAnalysisStatus.wrong,
    actualHomeGoals: 1,
    actualAwayGoals: 0,
    firstSeenAt: DateTime.utc(2026, 10, 19),
    lastSeenAt: DateTime.utc(2026, 10, 21),
    resolvedAt: resolvedAt ?? DateTime.utc(2026, 10, 21),
  );

  SmartBetLearningGateReport gate({
    bool eligible = true,
    String market = 'GOAL',
  }) => SmartBetLearningGateReport(
    decisions: [
      SmartBetLearningGateDecision(
        engine: SmartBetAnalysisEngine.smartBet.name,
        market: market,
        adjustedSamples: 120,
        distinctDays: 20,
        overallImprovement: 0.01,
        earlyImprovement: 0.01,
        recentImprovement: 0.01,
        status: eligible
            ? SmartBetLearningGateStatus.eligibleForTrial
            : SmartBetLearningGateStatus.insufficientData,
      ),
    ],
  );

  List<SmartBetAnalysisRecord> history() => [
    for (var i = 1; i <= 60; i++) record(i, correct: i <= 10),
  ];

  SmartBetLiveCalibrationSession session({
    bool enabled = true,
    bool emergencyStop = false,
    SmartBetLearningGateReport? report,
    List<SmartBetAnalysisRecord>? records,
  }) => SmartBetLiveCalibrationSession(
    enabled: enabled,
    emergencyStop: emergencyStop,
    startedAt: cutoff,
    history: records ?? history(),
    gate: report ?? gate(),
  );

  test('default OFF: anche un gate positivo non cambia la probabilità', () {
    final result = session(
      enabled: false,
    ).evaluate(market: 'GOAL', originalPercent: 80, fixtureId: 500);
    expect(result.percent, 80);
    expect(result.applied, false);
  });

  test('con evidenza e opt-in applica massimo 10 punti percentuali', () {
    final result = session().evaluate(
      market: 'GOAL',
      originalPercent: 80,
      fixtureId: 500,
    );
    expect(result.originalPercent, 80);
    expect(result.percent, 70);
    expect(result.applied, true);
    expect(result.historicalSamples, 60);
  });

  test('kill switch impedisce la calibrazione', () {
    final result = session(
      emergencyStop: true,
    ).evaluate(market: 'GOAL', originalPercent: 80, fixtureId: 500);
    expect(result.percent, 80);
    expect(result.applied, false);
  });

  test('gate negativo mantiene la previsione originale', () {
    final result = session(
      report: gate(eligible: false),
    ).evaluate(market: 'GOAL', originalPercent: 80, fixtureId: 500);
    expect(result.percent, 80);
  });

  test('gate di altro mercato non autorizza GOAL', () {
    final result = session(
      report: gate(market: 'UNDER 2.5'),
    ).evaluate(market: 'GOAL', originalPercent: 80, fixtureId: 500);
    expect(result.percent, 80);
  });

  test('storico sotto soglia: nessuna calibrazione', () {
    final result = session(
      records: history().take(49).toList(),
    ).evaluate(market: 'GOAL', originalPercent: 80, fixtureId: 500);
    expect(result.percent, 80);
  });

  test('esclude la stessa fixture dai dati di allenamento', () {
    final records = [for (var i = 1; i <= 50; i++) record(500)];
    final result = session(
      records: records,
    ).evaluate(market: 'GOAL', originalPercent: 80, fixtureId: 500);
    expect(result.percent, 80);
  });

  test('esclude risultati risolti dopo la generazione', () {
    final records = [
      for (var i = 1; i <= 60; i++)
        record(i, resolvedAt: DateTime.utc(2026, 11, 2)),
    ];
    final result = session(
      records: records,
    ).evaluate(market: 'GOAL', originalPercent: 80, fixtureId: 500);
    expect(result.percent, 80);
  });

  test('fixture e probabilità non validi rimangono invariati', () {
    final result = session().evaluate(
      market: 'GOAL',
      originalPercent: 105,
      fixtureId: 0,
    );
    expect(result.percent, 105);
    expect(result.applied, false);
  });
}
