import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/quotelab_historical_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  const calculator = QuoteLabHistoricalService();
  final kickoff = DateTime.utc(2026, 11, 10, 20);
  final asOf = DateTime.utc(2026, 11, 15, 12);

  SmartBetAnalysisRecord record({
    int fixtureId = 1,
    String market = '1',
    double? price = 1.20,
    int home = 2,
    int away = 1,
    String league = 'Serie A',
    DateTime? date,
    DateTime? seen,
    DateTime? resolved,
    bool prospective = true,
    SmartBetAnalysisStatus? status,
  }) {
    final matchDate = date ?? kickoff;
    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: fixtureId,
      homeTeam: 'Squadra A',
      awayTeam: 'Squadra B',
      league: league,
      country: 'Italia',
      matchDate: matchDate,
      market: market,
      probability: 0.80,
      smartScore: 75,
      confidence: null,
      classification: null,
      qualified: true,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: prospective,
      status: status ?? (home > away
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong),
      actualHomeGoals: home,
      actualAwayGoals: away,
      firstSeenAt: seen ?? matchDate.subtract(const Duration(hours: 3)),
      lastSeenAt: matchDate.add(const Duration(hours: 3)),
      resolvedAt: resolved ?? matchDate.add(const Duration(hours: 4)),
      quotedOdd: price,
    );
  }

  QuoteLabHistoricalReport run(List<SmartBetAnalysisRecord> history) =>
      calculator.evaluate(history: history, asOf: asOf);

  test('B56: quote 1.20 e 1.75 sono fasce diverse e non influenzano le AI', () {
    final report = run([
      record(fixtureId: 11, price: 1.20),
      record(fixtureId: 12, price: 1.75, home: 0, away: 1),
    ]);
    expect(report.sourceRecords, 2);
    expect(report.usableQuotedOutcomes, 2);
    expect(report.segments.where((s) => s.isAllLeagues).length, 2);
    final low = report.segments.singleWhere(
      (s) => s.isAllLeagues && s.priceBand.label == '1.20–1.29',
    );
    final high = report.segments.singleWhere(
      (s) => s.isAllLeagues && s.priceBand.label == '1.70–1.89',
    );
    expect(low.successes, 1);
    expect(low.hitRatePercent, 100);
    expect(low.averageGrossImpliedPercent, closeTo(83.333333, 1e-5));
    expect(low.historicalRoiPercent, closeTo(20, 1e-5));
    expect(high.successes, 0);
    expect(high.hitRatePercent, 0);
    expect(high.averageGrossImpliedPercent, closeTo(57.142857, 1e-5));
    expect(high.historicalRoiPercent, -100);
    expect(low.evidenceLevel, QuoteLabEvidenceLevel.insufficient);
    expect(report.changesSmartBetOrDiego, isFalse);
    expect(report.selectsCoupon, isFalse);
  });

  test('B56: non inventa uno storico quando manca la quota o il risultato', () {
    final report = run([
      record(fixtureId: 1, price: null),
      record(fixtureId: 2, price: double.nan),
      record(fixtureId: 3, price: 1.0),
      record(fixtureId: 4, status: SmartBetAnalysisStatus.pending),
      record(fixtureId: 5, prospective: false),
      record(fixtureId: 6, seen: kickoff.add(const Duration(minutes: 1))),
      record(fixtureId: 7, resolved: asOf.add(const Duration(hours: 1))),
    ]);
    expect(report.usableQuotedOutcomes, 0);
    expect(report.segments, isEmpty);
    expect(report.excludedRecords, 7);
  });

  test('B56: lo stesso evento non viene contato due volte per il mercato', () {
    final original = record();
    final report = run([original, original]);
    expect(report.usableQuotedOutcomes, 1);
    expect(report.duplicates, 1);
    expect(report.conflicts, 0);
  });

  test('B56: quote storiche contraddittorie fanno escludere il record', () {
    final report = run([
      record(price: 1.20),
      record(price: 1.80),
    ]);
    expect(report.usableQuotedOutcomes, 0);
    expect(report.conflicts, 1);
    expect(report.segments, isEmpty);
  });

  test('B56: esiti incongruenti col risultato finale vengono esclusi', () {
    final report = run([
      record(fixtureId: 1, home: 0, away: 2,
          status: SmartBetAnalysisStatus.correct),
      record(fixtureId: 2, market: 'CASA SEGNA PRIMA',
          status: SmartBetAnalysisStatus.correct),
    ]);
    expect(report.usableQuotedOutcomes, 0);
    expect(report.excludedRecords, 2);
  });

  test('B56: il gruppo per campionato non confonde campionati diversi', () {
    final report = run([
      record(fixtureId: 1, league: 'Serie A', price: 1.21),
      record(fixtureId: 2, league: 'Serie B', price: 1.21),
    ]);
    expect(report.segments.where((s) => s.isAllLeagues).single.observations, 2);
    expect(report.segments.where((s) => !s.isAllLeagues).length, 2);
  });

  test('B56: non certifica quote basse da campioni di una sola giornata', () {
    final history = [
      for (var i = 1; i <= 150; i++) record(fixtureId: i, price: 1.20),
    ];
    final report = run(history);
    final segment = report.segments.firstWhere((s) => s.isAllLeagues);
    expect(segment.observations, 150);
    expect(segment.matchDays, 1);
    expect(segment.evidenceLevel, QuoteLabEvidenceLevel.exploratory);
    expect(segment.wilsonLower95Percent, lessThan(100));
  });
}
