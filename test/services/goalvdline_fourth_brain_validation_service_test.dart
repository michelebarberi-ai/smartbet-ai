import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_fourth_brain_validation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

final now = DateTime.utc(2026, 11, 18, 15);
const validation = GoalVdLineFourthBrainValidationService();

SmartBetAnalysisRecord record(
  SmartBetAnalysisEngine engine, {
  int fixture = 1101,
  String market = 'GOAL',
  double probability = 0.7,
  bool correct = true,
  DateTime? date,
  DateTime? observed,
  String? classification,
}) {
  final kickoff = date ?? DateTime.utc(2026, 11, 12, 20);
  final first = kickoff.subtract(const Duration(hours: 24));
  final actualHome = correct ? 2 : 2;
  final actualAway = correct ? 1 : 0;
  return SmartBetAnalysisRecord(
    engine: engine, fixtureId: fixture,
    homeTeam: 'Casa', awayTeam: 'Ospite',
    league: 'Serie A', country: 'Italy',
    matchDate: kickoff, market: market,
    probability: probability, smartScore: null,
    confidence: null,
    classification: classification ??
        (engine == SmartBetAnalysisEngine.metaAi
            ? 'META_B67_V1_SHADOW_SMARTBET_XG' : null),
    qualified: engine == SmartBetAnalysisEngine.diego ? true : null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: true,
    status: correct ? SmartBetAnalysisStatus.correct :
        SmartBetAnalysisStatus.wrong,
    actualHomeGoals: actualHome,
    actualAwayGoals: actualAway,
    firstSeenAt: first,
    lastSeenAt: observed ?? kickoff.add(const Duration(hours: 2)),
    resolvedAt: observed ?? kickoff.add(const Duration(hours: 2)),
  );
}

List<SmartBetAnalysisRecord> triplet({int fixture = 1101,
    DateTime? date, bool correct = true, DateTime? observed}) => [
  record(SmartBetAnalysisEngine.smartBet,
      fixture: fixture, probability: 0.75,
      correct: correct, date: date, observed: observed),
  record(SmartBetAnalysisEngine.diego,
      fixture: fixture, probability: 0.60,
      correct: correct, date: date, observed: observed),
  record(SmartBetAnalysisEngine.metaAi,
      fixture: fixture, probability: 0.69,
      correct: correct, date: date, observed: observed),
];

void main() {
  test('B67: compare meta and parents only on same real fixture/market', () {
    final report = validation.evaluate(
      history: triplet(), asOf: now,
    );
    expect(report.completeTriplets, 1);
    expect(report.distinctMatchDays, 1);
    expect(report.smartBetBrier, closeTo(0.0625, 1e-10));
    expect(report.diegoBrier, closeTo(0.16, 1e-10));
    expect(report.metaBrier, closeTo(0.0961, 1e-10));
    expect(report.marginBelowBestParent, lessThan(0));
    expect(report.exploratorySample, isFalse);
    expect(report.researchSample, isFalse);
  });

  test('B67: unpaired event or different market never counts', () {
    final rows = triplet();
    rows[2] = record(SmartBetAnalysisEngine.metaAi,
        fixture: 1102, probability: 0.69);
    expect(validation.evaluate(history: rows, asOf: now)
        .completeTriplets, 0);
    rows[2] = record(SmartBetAnalysisEngine.metaAi,
        fixture: 1101, probability: 0.69, market: 'OVER 2.5');
    expect(validation.evaluate(history: rows, asOf: now)
        .completeTriplets, 0);
  });

  test('B67: simulator data cannot count as independent fourth evidence', () {
    final rows = triplet()..removeLast();
    rows.add(record(SmartBetAnalysisEngine.simulator,
        fixture: 1101, probability: 0.69));
    expect(validation.evaluate(history: rows, asOf: now)
        .completeTriplets, 0);
  });

  test('B67: future-known outcomes and nonprospective leakage excluded', () {
    final result = validation.evaluate(history: triplet(
      observed: DateTime.utc(2026, 11, 19, 12),
    ), asOf: now);
    expect(result.completeTriplets, 0);
    expect(result.rejected, 3);
  });

  test('B67: wrong outcome marker is discarded; no retrofitted Meta AI', () {
    final rows = triplet();
    rows[2] = record(SmartBetAnalysisEngine.metaAi,
        fixture: 1101, classification: 'invented_after_result');
    final result = validation.evaluate(history: rows, asOf: now);
    expect(result.completeTriplets, 0);
    expect(result.rejected, greaterThan(0));
  });

  test('B67: duplicate conflict invalidates entire comparison group', () {
    final rows = triplet();
    rows.add(record(SmartBetAnalysisEngine.diego,
      fixture: 1101, probability: 0.33,
    ));
    final result = validation.evaluate(history: rows, asOf: now);
    expect(result.completeTriplets, 0);
    expect(result.conflicts, 1);
  });

  test('B67: one duplicate identical record cannot inflate sample', () {
    final rows = triplet();
    rows.add(rows.first);
    expect(validation.evaluate(history: rows, asOf: now)
        .completeTriplets, 1);
  });

  test('B67: thresholds require 100 fixtures on 14 distinct days', () {
    final rows = <SmartBetAnalysisRecord>[];
    for (var i = 0; i < 100; i++) {
      rows.addAll(triplet(
        fixture: 6000 + i,
        date: DateTime.utc(2026, 10, 1 + (i % 20), 12),
        correct: i % 2 == 0,
      ));
    }
    final report = validation.evaluate(history: rows, asOf: now);
    expect(report.completeTriplets, 100);
    expect(report.distinctMatchDays, 20);
    expect(report.researchSample, isTrue);

    final small = validation.evaluate(history: rows.take(12 * 3), asOf: now);
    expect(small.researchSample, isFalse);
  });
}
