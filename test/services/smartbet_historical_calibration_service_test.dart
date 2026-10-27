import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/smartbet_historical_calibration_service.dart';
import '../../lib/services/smartbet_analysis_history_store.dart';

void main() {
  const service = SmartBetHistoricalCalibrationService();

  final cutoff = DateTime.utc(2026, 10, 25);

  SmartBetAnalysisRecord record(
    int id, {
    bool correct = true,
    String market = 'GOAL',
    DateTime? lastSeenAt,
    DateTime? resolvedAt,
    bool legacy = false,
    double probability = 0.80,
  }) {
    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: id,
      homeTeam: 'Home',
      awayTeam: 'Away',
      league: 'Serie A',
      country: 'Italy',
      matchDate: DateTime.utc(2026, 10, 20),
      market: market,
      probability: probability,
      smartScore: 70,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: 2,
      actualAwayGoals: 1,
      firstSeenAt: DateTime.utc(2026, 10, 18),
      lastSeenAt: lastSeenAt ?? DateTime.utc(2026, 10, 21),
      resolvedAt: legacy
          ? null
          : (resolvedAt ?? lastSeenAt ?? DateTime.utc(2026, 10, 21)),
    );
  }

  List<SmartBetAnalysisRecord> history(int count) {
    return List.generate(count, (i) => record(i + 1, correct: i < count ~/ 2));
  }

  test('meno di 50 osservazioni non correggono', () {
    final result = service.evaluate(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.80,
      asOf: cutoff,
      records: history(49),
    );

    expect(result.applied, false);
    expect(result.sampleSize, 49);
    expect(result.calibrated, 0.80);
  });

  test('50 osservazioni producono correzione limitata', () {
    final result = service.evaluate(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.80,
      asOf: cutoff,
      records: history(50),
    );

    expect(result.applied, true);
    expect(result.sampleSize, 50);
    expect(result.historicalGap, closeTo(-0.30, 0.0001));
    expect(result.calibrated, closeTo(0.70, 0.0001));
  });

  test('esclude risultati registrati dopo il cutoff', () {
    final records = history(49);
    records.add(record(999, lastSeenAt: DateTime.utc(2026, 10, 26)));

    final result = service.evaluate(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.80,
      asOf: cutoff,
      records: records,
    );

    expect(result.sampleSize, 49);
    expect(result.applied, false);
  });

  test('non mescola mercati diversi', () {
    final records = history(49);
    records.add(record(999, market: 'OVER 2.5'));

    final result = service.evaluate(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.80,
      asOf: cutoff,
      records: records,
    );

    expect(result.sampleSize, 49);
    expect(result.applied, false);
  });

  test('esclude record legacy senza resolvedAt', () {
    final records = history(49);
    records.add(record(999, legacy: true));

    final result = service.evaluate(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.80,
      asOf: cutoff,
      records: records,
    );

    expect(result.sampleSize, 49);
    expect(result.applied, false);
  });

  test('resolvedAt sopravvive agli aggiornamenti e al JSON', () {
    final source = record(900).toJson();

    final pending = SmartBetAnalysisRecord.fromJson({
      ...source,
      'status': 'pending',
      'resolvedAt': null,
      'actualHomeGoals': null,
      'actualAwayGoals': null,
    })!;

    final firstDate = DateTime.utc(2026, 10, 22);

    final resolved = pending.withActualResult(
      homeGoals: 2,
      awayGoals: 1,
      status: SmartBetAnalysisStatus.correct,
      updatedAt: firstDate,
    );

    expect(resolved.resolvedAt, firstDate);

    final updatedRecord = resolved.withActualResult(
      homeGoals: 2,
      awayGoals: 1,
      status: SmartBetAnalysisStatus.correct,
      updatedAt: DateTime.utc(2026, 10, 23),
    );

    expect(updatedRecord.resolvedAt, firstDate);

    final withSource = updatedRecord.withSource(
      source: SmartBetAnalysisSource.combinations,
      seenAt: DateTime.utc(2026, 10, 24),
    );

    expect(withSource.resolvedAt, firstDate);

    final restored = SmartBetAnalysisRecord.fromJson(withSource.toJson());

    expect(restored, isNotNull);
    expect(restored!.resolvedAt, firstDate);

    final legacy = record(901, legacy: true);

    final legacyUpdated = legacy.withActualResult(
      homeGoals: 2,
      awayGoals: 1,
      status: SmartBetAnalysisStatus.correct,
      updatedAt: DateTime.utc(2026, 10, 24),
    );

    expect(legacyUpdated.resolvedAt, isNull);
  });

  test('non utilizza la stessa partita', () {
    final result = service.evaluate(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.80,
      asOf: cutoff,
      records: history(50),
      fixtureId: 1,
    );

    expect(result.sampleSize, 49);
    expect(result.applied, false);
  });
}
