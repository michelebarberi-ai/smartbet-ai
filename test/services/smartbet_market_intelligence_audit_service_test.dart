import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_market_intelligence_audit_service.dart';

SmartBetAnalysisRecord sample({
  int fixtureId = 100,
  SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  String market = 'GOAL',
  double? probability = 0.80,
  double? odd = 1.80,
  SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
  bool prospective = true,
  bool resolved = true,
  bool beforeKickoff = true,
  bool? qualifiedOverride,
}) {
  final kickoff = DateTime.utc(2026, 10, 28, 18);

  return SmartBetAnalysisRecord(
    engine: engine,
    fixtureId: fixtureId,
    homeTeam: 'Casa',
    awayTeam: 'Ospite',
    league: 'Test',
    country: 'Test',
    matchDate: kickoff,
    market: market,
    probability: probability,
    smartScore: engine == SmartBetAnalysisEngine.smartBet ? 80 : null,
    confidence: null,
    classification: null,
    qualified: engine == SmartBetAnalysisEngine.diego
        ? (qualifiedOverride ?? true)
        : null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: prospective,
    status: status,
    actualHomeGoals: resolved ? 2 : null,
    actualAwayGoals: resolved ? 1 : null,
    firstSeenAt: beforeKickoff
        ? DateTime.utc(2026, 10, 27, 12)
        : DateTime.utc(2026, 10, 28, 19),
    lastSeenAt: DateTime.utc(2026, 10, 29, 12),
    resolvedAt: resolved ? DateTime.utc(2026, 10, 29, 12) : null,
    quotedOdd: odd,
  );
}

void main() {
  const service = MarketIntelligenceAuditService();

  test('Brier Score, frequenza e quote vengono calcolati correttamente', () {
    final report = service.evaluate([
      sample(),
      sample(
        fixtureId: 101,
        probability: 0.60,
        odd: 2.00,
        status: SmartBetAnalysisStatus.wrong,
      ),
    ]);

    expect(report.includedRecords, 2);
    expect(report.groups.length, 1);

    final metric = report.groups.single;

    expect(metric.samples, 2);
    expect(metric.correct, 1);
    expect(metric.meanProbability, closeTo(0.70, 1e-9));
    expect(metric.observedFrequency, closeTo(0.50, 1e-9));
    expect(metric.brierScore, closeTo(0.20, 1e-9));
    expect(metric.quotedSamples, 2);
    expect(
      metric.meanImpliedProbability,
      closeTo(((1 / 1.8) + (1 / 2.0)) / 2, 1e-9),
    );
    expect(metric.hypotheticalUnitRoi, closeTo(-0.10, 1e-9));
  });

  test('Senza quote mantiene la calibrazione ma non inventa il ROI', () {
    final report = service.evaluate([sample(odd: null)]);
    final metric = report.groups.single;

    expect(metric.samples, 1);
    expect(metric.quotedSamples, 0);
    expect(metric.marketGap, isNull);
    expect(metric.hypotheticalUnitRoi, isNull);
  });

  test('Esclude analisi retrospettive, pending e non risolte', () {
    final report = service.evaluate([
      sample(),
      sample(fixtureId: 101, prospective: false),
      sample(fixtureId: 102, beforeKickoff: false),
      sample(fixtureId: 103, resolved: false),
      sample(fixtureId: 104, status: SmartBetAnalysisStatus.pending),
    ]);

    expect(report.includedRecords, 1);
    expect(report.excludedRecords, 4);
  });

  test('SmartBet e Diego restano gruppi indipendenti', () {
    final report = service.evaluate([
      sample(),
      sample(engine: SmartBetAnalysisEngine.diego, odd: null),
    ]);

    expect(report.groups.length, 2);
    expect(report.includedRecords, 2);
  });

  test('Diego non qualificato è escluso dalle metriche', () {
    final report = service.evaluate([
      sample(
        engine: SmartBetAnalysisEngine.diego,
        qualifiedOverride: false,
        odd: null,
      ),
      sample(
        fixtureId: 101,
        engine: SmartBetAnalysisEngine.diego,
        qualifiedOverride: true,
        odd: null,
      ),
    ]);

    expect(report.includedRecords, 1);
    expect(report.excludedRecords, 1);
    expect(report.groups.single.samples, 1);
  });

  test('La stessa previsione non viene conteggiata due volte', () {
    final record = sample();

    final report = service.evaluate([record, record]);

    expect(report.includedRecords, 1);
    expect(report.excludedRecords, 1);
  });

  test('Una quota insufficiente non altera le metriche sportive', () {
    final report = service.evaluate([sample(odd: 1.20)]);

    final metric = report.groups.single;

    expect(metric.samples, 1);
    expect(metric.brierScore, closeTo(0.04, 1e-9));
    expect(metric.quotedSamples, 0);
    expect(metric.marketGap, isNull);
  });
}
