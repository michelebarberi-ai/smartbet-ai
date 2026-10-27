import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/smartbet_adaptive_learning_service.dart';
import '../../lib/services/smartbet_analysis_history_store.dart';

void main() {
  const service = SmartBetAdaptiveLearningService();

  SmartBetAnalysisRecord record({
    required int fixtureId,
    required SmartBetAnalysisEngine engine,
    required String market,
    required String league,
    required SmartBetAnalysisStatus status,
    double? probability,
    bool prospectiveEligible = true,
  }) {
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId,
      homeTeam: 'Home',
      awayTeam: 'Away',
      league: league,
      country: 'Italy',
      matchDate: DateTime.utc(2026, 10, 25, 20, 45),
      market: market,
      probability: probability,
      smartScore: engine == SmartBetAnalysisEngine.smartBet ? 70 : null,
      confidence: engine == SmartBetAnalysisEngine.diego ? 75 : null,
      classification: engine == SmartBetAnalysisEngine.diego
          ? 'QUALIFIED VALUE'
          : null,
      qualified: engine == SmartBetAnalysisEngine.diego ? true : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospectiveEligible,
      status: status,
      actualHomeGoals:
          status == SmartBetAnalysisStatus.correct ||
              status == SmartBetAnalysisStatus.wrong
          ? 2
          : null,
      actualAwayGoals:
          status == SmartBetAnalysisStatus.correct ||
              status == SmartBetAnalysisStatus.wrong
          ? 1
          : null,
      firstSeenAt: DateTime.utc(2026, 10, 20, 10),
      lastSeenAt: DateTime.utc(2026, 10, 26, 10),
    );
  }

  test('usa solo analisi prospettiche concluse', () {
    final records = [
      record(
        fixtureId: 1,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.correct,
        probability: 0.70,
      ),
      record(
        fixtureId: 2,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.wrong,
        probability: 0.70,
      ),
      record(
        fixtureId: 3,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.pending,
        probability: 0.70,
      ),
      record(
        fixtureId: 4,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.unsupported,
        probability: 0.70,
      ),
      record(
        fixtureId: 5,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.correct,
        probability: 0.70,
        prospectiveEligible: false,
      ),
    ];

    final report = service.analyze(records);

    expect(report.eligibleRecords, 2);

    final overall = report.segments.firstWhere(
      (segment) =>
          segment.engine == SmartBetAnalysisEngine.smartBet &&
          segment.dimension == SmartBetAdaptiveLearningDimension.overall,
    );

    expect(overall.sampleSize, 2);
    expect(overall.correct, 1);
    expect(overall.wrong, 1);
    expect(overall.accuracy, 50.0);
  });

  test('costruisce segmenti mercato campionato e fascia', () {
    final records = [
      record(
        fixtureId: 10,
        engine: SmartBetAnalysisEngine.smartBet,
        market: 'Goal',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.correct,
        probability: 0.72,
      ),
    ];

    final report = service.analyze(records);

    expect(
      report.segments.any(
        (segment) =>
            segment.dimension == SmartBetAdaptiveLearningDimension.market &&
            segment.market == 'GOAL',
      ),
      isTrue,
    );

    expect(
      report.segments.any(
        (segment) =>
            segment.dimension == SmartBetAdaptiveLearningDimension.league &&
            segment.league == 'Serie A',
      ),
      isTrue,
    );

    expect(
      report.segments.any(
        (segment) =>
            segment.dimension ==
                SmartBetAdaptiveLearningDimension.marketLeague &&
            segment.market == 'GOAL' &&
            segment.league == 'Serie A',
      ),
      isTrue,
    );

    expect(
      report.segments.any(
        (segment) =>
            segment.dimension ==
                SmartBetAdaptiveLearningDimension.probabilityBand &&
            segment.probabilityBand == '70-79%',
      ),
      isTrue,
    );
  });

  test('calcola accuracy calibrazione e Brier Score', () {
    final records = <SmartBetAnalysisRecord>[];

    for (var i = 0; i < 10; i++) {
      records.add(
        record(
          fixtureId: 100 + i,
          engine: SmartBetAnalysisEngine.smartBet,
          market: 'GOAL',
          league: 'Serie A',
          status: i < 8
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong,
          probability: 0.70,
        ),
      );
    }

    final report = service.analyze(records);

    final overall = report.segments.firstWhere(
      (segment) =>
          segment.engine == SmartBetAnalysisEngine.smartBet &&
          segment.dimension == SmartBetAdaptiveLearningDimension.overall,
    );

    expect(overall.sampleSize, 10);
    expect(overall.correct, 8);
    expect(overall.wrong, 2);

    expect(overall.accuracy, 80.0);

    expect(overall.averagePredictedProbability, closeTo(70.0, 0.0001));

    expect(overall.calibrationGap, closeTo(10.0, 0.0001));

    expect(overall.brierScore, closeTo(0.17, 0.0001));
  });

  test('calibrazione usa solo record con probabilita disponibile', () {
    final records = [
      record(
        fixtureId: 501,
        engine: SmartBetAnalysisEngine.smartBet,
        market: 'GOAL',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.correct,
        probability: 0.80,
      ),
      record(
        fixtureId: 502,
        engine: SmartBetAnalysisEngine.smartBet,
        market: 'GOAL',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.wrong,
        probability: null,
      ),
      record(
        fixtureId: 503,
        engine: SmartBetAnalysisEngine.smartBet,
        market: 'GOAL',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.correct,
        probability: null,
      ),
    ];

    final report = service.analyze(records);

    final overall = report.segments.firstWhere(
      (segment) =>
          segment.engine == SmartBetAnalysisEngine.smartBet &&
          segment.dimension == SmartBetAdaptiveLearningDimension.overall,
    );

    expect(overall.sampleSize, 3);
    expect(overall.correct, 2);
    expect(overall.wrong, 1);

    expect(overall.probabilitySampleSize, 1);
    expect(overall.accuracy, closeTo(66.6667, 0.001));
    expect(overall.averagePredictedProbability, 80.0);
    expect(overall.calibrationGap, closeTo(20.0, 0.0001));
    expect(overall.brierScore, closeTo(0.04, 0.0001));
  });

  test('classifica correttamente la forza del campione', () {
    expect(
      SmartBetAdaptiveLearningService.signalForSample(49),
      SmartBetAdaptiveLearningSignal.insufficient,
    );

    expect(
      SmartBetAdaptiveLearningService.signalForSample(50),
      SmartBetAdaptiveLearningSignal.exploratory,
    );

    expect(
      SmartBetAdaptiveLearningService.signalForSample(100),
      SmartBetAdaptiveLearningSignal.signal,
    );

    expect(
      SmartBetAdaptiveLearningService.signalForSample(200),
      SmartBetAdaptiveLearningSignal.strongCandidate,
    );
  });

  test('SmartBet e Diego restano separati', () {
    final records = [
      record(
        fixtureId: 201,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.correct,
        probability: 0.70,
      ),
      record(
        fixtureId: 201,
        engine: SmartBetAnalysisEngine.diego,
        market: 'OVER 2.5',
        league: 'Serie A',
        status: SmartBetAnalysisStatus.wrong,
        probability: 0.65,
      ),
    ];

    final report = service.analyze(records);

    final smartBetOverall = report.segments.firstWhere(
      (segment) =>
          segment.engine == SmartBetAnalysisEngine.smartBet &&
          segment.dimension == SmartBetAdaptiveLearningDimension.overall,
    );

    final diegoOverall = report.segments.firstWhere(
      (segment) =>
          segment.engine == SmartBetAnalysisEngine.diego &&
          segment.dimension == SmartBetAdaptiveLearningDimension.overall,
    );

    expect(smartBetOverall.accuracy, 100.0);
    expect(diegoOverall.accuracy, 0.0);
  });

  test('50 casi rendono il segmento esplorativo', () {
    final records = <SmartBetAnalysisRecord>[];

    for (var i = 0; i < 50; i++) {
      records.add(
        record(
          fixtureId: 300 + i,
          engine: SmartBetAnalysisEngine.smartBet,
          market: '1X',
          league: 'Serie A',
          status: i < 35
              ? SmartBetAnalysisStatus.correct
              : SmartBetAnalysisStatus.wrong,
          probability: 0.68,
        ),
      );
    }

    final report = service.analyze(records);

    final marketSegment = report.segments.firstWhere(
      (segment) =>
          segment.engine == SmartBetAnalysisEngine.smartBet &&
          segment.dimension == SmartBetAdaptiveLearningDimension.market &&
          segment.market == '1X',
    );

    expect(marketSegment.sampleSize, 50);

    expect(marketSegment.signal, SmartBetAdaptiveLearningSignal.exploratory);

    expect(marketSegment.accuracy, closeTo(70.0, 0.0001));
  });
}
