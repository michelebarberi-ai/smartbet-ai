import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/smartbet_analysis_comparison_store.dart';
import '../../lib/services/smartbet_analysis_history_store.dart';
import '../../lib/services/smartbet_meta_learning_service.dart';

void main() {
  const service = SmartBetMetaLearningService();

  SmartBetAnalysisRecord record({
    required int fixtureId,
    required SmartBetAnalysisEngine engine,
    required String market,
    required String league,
    required SmartBetAnalysisStatus status,
    double? probability,
    bool prospectiveEligible = true,
    bool? qualified,
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
      qualified: engine == SmartBetAnalysisEngine.diego
          ? (qualified ?? true)
          : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospectiveEligible,
      status: status,
      actualHomeGoals: 2,
      actualAwayGoals: 1,
      firstSeenAt: DateTime.utc(2026, 10, 20, 10),
      lastSeenAt: DateTime.utc(2026, 10, 26, 10),
    );
  }

  SmartBetAnalysisComparisonLink link({
    required SmartBetAnalysisRecord smartBet,
    required SmartBetAnalysisRecord diego,
  }) {
    return SmartBetAnalysisComparisonLink(
      fixtureId: smartBet.fixtureId,
      smartBetRecordKey: smartBet.key,
      diegoRecordKey: diego.key,
      smartBetMarket: smartBet.market,
      diegoMarket: diego.market,
      sources: const [SmartBetAnalysisSource.analysis],
      firstSeenAt: DateTime.utc(2026, 10, 20, 10),
      lastSeenAt: DateTime.utc(2026, 10, 20, 10),
    );
  }

  test('confronta solo coppie prospettiche concluse', () {
    final smart1 = record(
      fixtureId: 1,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
    );

    final diego1 = record(
      fixtureId: 1,
      engine: SmartBetAnalysisEngine.diego,
      market: 'GOAL',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.wrong,
    );

    final smart2 = record(
      fixtureId: 2,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.pending,
    );

    final diego2 = record(
      fixtureId: 2,
      engine: SmartBetAnalysisEngine.diego,
      market: 'GOAL',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
    );

    final report = service.analyze(
      records: [smart1, diego1, smart2, diego2],
      links: [
        link(smartBet: smart1, diego: diego1),
        link(smartBet: smart2, diego: diego2),
      ],
    );

    expect(report.linkedPairs, 2);
    expect(report.eligiblePairs, 1);

    expect(report.excludedPendingOrUnsupported, 1);

    expect(report.overall, isNotNull);
    expect(report.overall!.sampleSize, 1);
  });

  test('calcola correttamente vantaggio SmartBet Diego', () {
    final records = <SmartBetAnalysisRecord>[];

    final links = <SmartBetAnalysisComparisonLink>[];

    for (var i = 0; i < 50; i++) {
      final smart = record(
        fixtureId: 100 + i,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: i < 35
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong,
      );

      final diego = record(
        fixtureId: 100 + i,
        engine: SmartBetAnalysisEngine.diego,
        market: 'GOAL',
        league: 'Serie A',
        status: i < 30
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong,
      );

      records.addAll([smart, diego]);

      links.add(link(smartBet: smart, diego: diego));
    }

    final report = service.analyze(records: records, links: links);

    final overall = report.overall!;

    expect(overall.sampleSize, 50);

    expect(overall.smartBetAccuracy, 70.0);

    expect(overall.diegoAccuracy, 60.0);

    expect(overall.advantagePercentagePoints, 10.0);

    expect(overall.preference, SmartBetMetaLearningPreference.smartBet);
  });

  test('campione sotto 50 non produce preferenza', () {
    final smart = record(
      fixtureId: 300,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
    );

    final diego = record(
      fixtureId: 300,
      engine: SmartBetAnalysisEngine.diego,
      market: 'GOAL',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.wrong,
    );

    final report = service.analyze(
      records: [smart, diego],
      links: [link(smartBet: smart, diego: diego)],
    );

    expect(
      report.overall!.preference,
      SmartBetMetaLearningPreference.insufficientData,
    );
  });

  test('differenza sotto 3 punti viene considerata bilanciata', () {
    final records = <SmartBetAnalysisRecord>[];

    final links = <SmartBetAnalysisComparisonLink>[];

    for (var i = 0; i < 100; i++) {
      final smart = record(
        fixtureId: 400 + i,
        engine: SmartBetAnalysisEngine.smartBet,
        market: '1X',
        league: 'Serie A',
        status: i < 61
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong,
      );

      final diego = record(
        fixtureId: 400 + i,
        engine: SmartBetAnalysisEngine.diego,
        market: 'GOAL',
        league: 'Serie A',
        status: i < 60
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong,
      );

      records.addAll([smart, diego]);

      links.add(link(smartBet: smart, diego: diego));
    }

    final report = service.analyze(records: records, links: links);

    expect(report.overall!.preference, SmartBetMetaLearningPreference.balanced);
  });

  test('costruisce segmenti campionato e coppia mercati', () {
    final smart = record(
      fixtureId: 600,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
      probability: 0.72,
    );

    final diego = record(
      fixtureId: 600,
      engine: SmartBetAnalysisEngine.diego,
      market: 'OVER 2.5',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
      probability: 0.64,
    );

    final report = service.analyze(
      records: [smart, diego],
      links: [link(smartBet: smart, diego: diego)],
    );

    expect(
      report.segments.any(
        (segment) =>
            segment.dimension == SmartBetMetaLearningDimension.league &&
            segment.league == 'Serie A',
      ),
      isTrue,
    );

    expect(
      report.segments.any(
        (segment) =>
            segment.dimension == SmartBetMetaLearningDimension.marketPair &&
            segment.smartBetMarket == '1X' &&
            segment.diegoMarket == 'OVER 2.5',
      ),
      isTrue,
    );

    expect(
      report.segments.any(
        (segment) =>
            segment.dimension ==
                SmartBetMetaLearningDimension.probabilityPair &&
            segment.probabilityPair == '70-79% | 60-69%',
      ),
      isTrue,
    );
  });

  test('Diego noSelection viene escluso dal meta learning', () {
    final smart = record(
      fixtureId: 700,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
    );

    final diego = record(
      fixtureId: 700,
      engine: SmartBetAnalysisEngine.diego,
      market: 'GOAL',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
      qualified: false,
    );

    final report = service.analyze(
      records: [smart, diego],
      links: [link(smartBet: smart, diego: diego)],
    );

    expect(report.eligiblePairs, 0);

    expect(report.excludedUnqualifiedDiego, 1);
  });

  test('noSelection può essere studiato esplicitamente in shadow', () {
    final smart = record(
      fixtureId: 800,
      engine: SmartBetAnalysisEngine.smartBet,
      market: '1X',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.wrong,
    );

    final diego = record(
      fixtureId: 800,
      engine: SmartBetAnalysisEngine.diego,
      market: 'GOAL',
      league: 'Serie A',
      status: SmartBetAnalysisStatus.correct,
      qualified: false,
    );

    final report = service.analyze(
      records: [smart, diego],
      links: [link(smartBet: smart, diego: diego)],
      includeUnqualifiedDiego: true,
    );

    expect(report.eligiblePairs, 1);

    expect(report.overall!.diegoAccuracy, 100.0);
  });
}
