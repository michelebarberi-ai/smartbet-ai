import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_paired_calibration_service.dart';

SmartBetAnalysisRecord sample({
  int fixtureId = 100,
  SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
  String market = 'GOAL',
  double? probability = 0.8,
  SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
  bool qualified = true,
  bool prospective = true,
  bool resolved = true,
  DateTime? kickoff,
}) {
  final date = kickoff ?? DateTime.utc(2026, 10, 28, 18);

  return SmartBetAnalysisRecord(
    engine: engine,
    fixtureId: fixtureId,
    homeTeam: 'Casa',
    awayTeam: 'Ospite',
    league: 'Test',
    country: 'Test',
    matchDate: date,
    market: market,
    probability: probability,
    smartScore: engine == SmartBetAnalysisEngine.smartBet ? 80 : null,
    confidence: null,
    classification: null,
    qualified: engine == SmartBetAnalysisEngine.diego ? qualified : null,
    sources: const [SmartBetAnalysisSource.analysis],
    prospectiveEligible: prospective,
    status: status,
    actualHomeGoals: resolved ? 2 : null,
    actualAwayGoals: resolved ? 1 : null,
    firstSeenAt: date.subtract(const Duration(hours: 24)),
    lastSeenAt: date.add(const Duration(hours: 24)),
    resolvedAt: resolved ? date.add(const Duration(hours: 24)) : null,
  );
}

void main() {
  const service = SmartBetPairedCalibrationService();

  test('Brier confrontato sulla stessa fixture e mercato', () {
    final report = service.evaluate([
      sample(probability: 0.8),
      sample(engine: SmartBetAnalysisEngine.diego, probability: 0.6),
    ]);

    expect(report.totalPairs, 1);

    final metric = report.markets.single;
    expect(metric.pairedFixtures, 1);
    expect(metric.smartBetBrier, closeTo(0.04, 1e-9));
    expect(metric.diegoBrier, closeTo(0.16, 1e-9));
    expect(metric.smartBetBrierAdvantage, closeTo(0.12, 1e-9));
    expect(metric.enoughForExploratoryReview, isFalse);
  });

  test('Mercati diversi non vengono confrontati', () {
    final report = service.evaluate([
      sample(market: 'GOAL'),
      sample(engine: SmartBetAnalysisEngine.diego, market: 'OVER 2.5'),
    ]);

    expect(report.totalPairs, 0);
    expect(report.markets, isEmpty);
  });

  test('Diego non qualificato viene escluso', () {
    final report = service.evaluate([
      sample(),
      sample(engine: SmartBetAnalysisEngine.diego, qualified: false),
    ]);

    expect(report.totalPairs, 0);
  });

  test('Non usa partite non risolte o analisi non prospettiche', () {
    final report = service.evaluate([
      sample(fixtureId: 100, resolved: false),
      sample(fixtureId: 100, engine: SmartBetAnalysisEngine.diego),
      sample(fixtureId: 101, prospective: false),
      sample(fixtureId: 101, engine: SmartBetAnalysisEngine.diego),
      sample(fixtureId: 102, status: SmartBetAnalysisStatus.pending),
      sample(fixtureId: 102, engine: SmartBetAnalysisEngine.diego),
    ]);

    expect(report.totalPairs, 0);
  });

  test('Duplicati ed esiti incoerenti non alterano le metriche', () {
    final sb = sample();
    final diego = sample(engine: SmartBetAnalysisEngine.diego);

    final report = service.evaluate([
      sb,
      sb,
      diego,
      diego,
      sample(fixtureId: 101, status: SmartBetAnalysisStatus.correct),
      sample(
        fixtureId: 101,
        engine: SmartBetAnalysisEngine.diego,
        status: SmartBetAnalysisStatus.wrong,
      ),
    ]);

    expect(report.totalPairs, 1);
  });

  test('La soglia esplorativa richiede fixture e giorni distinti', () {
    final records = <SmartBetAnalysisRecord>[];

    for (var i = 0; i < 30; i++) {
      final kickoff = DateTime.utc(2026, 10, 1, 18).add(Duration(days: i ~/ 2));

      records.add(sample(fixtureId: i + 1000, kickoff: kickoff));
      records.add(
        sample(
          fixtureId: i + 1000,
          kickoff: kickoff,
          engine: SmartBetAnalysisEngine.diego,
          probability: 0.7,
        ),
      );
    }

    final report = service.evaluate(records);
    final metric = report.markets.single;

    expect(report.totalPairs, 30);
    expect(metric.distinctDays, 15);
    expect(metric.enoughForExploratoryReview, isTrue);
  });
}
