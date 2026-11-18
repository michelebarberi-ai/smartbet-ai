import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_market_ease_index_service.dart';

void main() {
  const service = SmartBetMarketEaseIndexService();
  final asOf = DateTime.utc(2026, 11, 18);

  SmartBetAnalysisRecord sample({
    required int fixture,
    SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    bool qualified = true,
    bool prospective = true,
    double? probability = 0.78,
    double? quotedOdd,
    DateTime? kickoff,
    DateTime? resolvedAt,
    String league = 'Serie A',
  }) {
    final start = kickoff ?? DateTime.utc(2026, 1, 1).add(Duration(days: fixture));
    final resolved = resolvedAt ?? start.add(const Duration(hours: 3));
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixture,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      country: 'Italia',
      league: league,
      matchDate: start,
      market: 'GOAL',
      probability: probability,
      smartScore: 75,
      confidence: null,
      classification: null,
      qualified: engine == SmartBetAnalysisEngine.diego ? qualified : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: status,
      actualHomeGoals: status == SmartBetAnalysisStatus.pending ? null : 2,
      actualAwayGoals: status == SmartBetAnalysisStatus.pending ? null : 1,
      firstSeenAt: start.subtract(const Duration(hours: 5)),
      lastSeenAt: resolved,
      resolvedAt: status == SmartBetAnalysisStatus.pending ? null : resolved,
      quotedOdd: quotedOdd,
    );
  }

  List<SmartBetAnalysisRecord> batch({
    required int count,
    required int wins,
    double probability = 0.78,
    double? quotedOdd,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    bool qualified = true,
    int offset = 0,
  }) => [
        for (var i = 0; i < count; i++)
          sample(
            fixture: i + offset + 1,
            engine: engine,
            qualified: qualified,
            status: i < wins
                ? SmartBetAnalysisStatus.correct
                : SmartBetAnalysisStatus.wrong,
            probability: probability,
            quotedOdd: quotedOdd,
          ),
      ];

  test('90% su 10 non supera la soglia; 78% su 200 puo entrare SHADOW', () {
    final small = service.evaluate(
      records: batch(count: 10, wins: 9),
      asOf: asOf,
    ).entries.single;
    final larger = service.evaluate(
      records: batch(count: 200, wins: 156),
      asOf: asOf,
    ).entries.single;
    expect(small.status, MarketEaseEvidenceStatus.insufficient);
    expect(small.score, isNull);
    expect(larger.status, MarketEaseEvidenceStatus.shadowCandidate);
    expect(larger.score, isNotNull);
    expect(larger.score!, inInclusiveRange(0, 100));
    expect(larger.evidence.wilsonLower95Percent, lessThan(78));
  });

  test('50-99 fixture restano esplorative senza MEI numerico', () {
    final report = service.evaluate(
      records: batch(count: 60, wins: 45),
      asOf: asOf,
    );
    expect(report.entries.single.status, MarketEaseEvidenceStatus.exploratory);
    expect(report.entries.single.score, isNull);
  });

  test('sovrastima penalizzata a pari risultati e Wilson', () {
    final calibrated = service.evaluate(
      records: batch(count: 120, wins: 84, probability: 0.70),
      asOf: asOf,
    ).entries.single;
    final overconfident = service.evaluate(
      records: batch(count: 120, wins: 84, probability: 0.90),
      asOf: asOf,
    ).entries.single;
    expect(calibrated.overconfidencePoints, closeTo(0, 1e-7));
    expect(overconfident.overconfidencePoints, closeTo(20, 1e-7));
    expect(overconfident.score!, lessThan(calibrated.score!));
  });

  test('le quote non alterano mai MEI o ranking storico', () {
    final lowOdds = service.evaluate(
      records: batch(count: 120, wins: 90, quotedOdd: 1.01),
      asOf: asOf,
    ).entries.single;
    final highOdds = service.evaluate(
      records: batch(count: 120, wins: 90, quotedOdd: 5.00),
      asOf: asOf,
    ).entries.single;
    expect(lowOdds.score, closeTo(highOdds.score!, 1e-10));
    expect(lowOdds.brierSkill, highOdds.brierSkill);
    expect(lowOdds.evidence.sampleSize, highOdds.evidence.sampleSize);
  });

  test('unqualified Diego is excluded even with many settled outcomes', () {
    final report = service.evaluate(
      records: [
        ...batch(count: 120, wins: 95),
        ...batch(
          count: 120,
          wins: 115,
          engine: SmartBetAnalysisEngine.diego,
          qualified: false,
        ),
      ],
      asOf: asOf,
    );
    expect(report.entries, hasLength(1));
    expect(report.entries.single.evidence.engine,
        SmartBetAnalysisEngine.smartBet);
    expect(report.excludedBeforeReliability, 120);
  });

  test('SmartBet and qualified Diego are kept separate', () {
    final report = service.evaluate(
      records: [
        ...batch(count: 110, wins: 85),
        ...batch(
          count: 110,
          wins: 80,
          engine: SmartBetAnalysisEngine.diego,
          qualified: true,
        ),
      ],
      asOf: asOf,
    );
    expect(report.entries, hasLength(2));
    expect(report.entries.every((x) => x.score != null), isTrue);
  });

  test('duplicate fixtures cannot inflate the score', () {
    final values = batch(count: 120, wins: 90);
    final report = service.evaluate(
      records: [
        ...values,
        sample(fixture: 1, quotedOdd: 3.0),
      ],
      asOf: asOf,
    );
    expect(report.evaluatedRecords, 120);
    expect(report.entries.single.evidence.sampleSize, 120);
  });

  test('hindsight, future settlement and unfinished matches excluded', () {
    final start = DateTime.utc(2026, 11, 13, 16);
    final report = service.evaluate(records: [
      sample(fixture: 1, kickoff: start, prospective: false),
      sample(fixture: 2, kickoff: start,
          resolvedAt: asOf.add(const Duration(days: 1))),
      sample(fixture: 3, kickoff: start,
          status: SmartBetAnalysisStatus.pending),
      sample(fixture: 4, kickoff: start),
    ], asOf: asOf);
    expect(report.evaluatedRecords, 1);
    expect(report.entries.single.score, isNull);
  });

  test('no observations means unknown, not zero reliability', () {
    final report = service.evaluate(records: [], asOf: asOf);
    expect(report.entries, isEmpty);
    expect(report.evaluatedRecords, 0);
  });
}
