import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_market_ease_index_service.dart';

void main() {
  const service = SmartBetMarketEaseIndexService();
  final asOf = DateTime.utc(2026, 11, 18);

  SmartBetAnalysisRecord record({
    required int fixture,
    bool correct = true,
    double? probability = 0.75,
    String market = 'GOAL',
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    DateTime? kickoff,
  }) {
    final start = kickoff ??
        DateTime.utc(2026, 4, 1).add(Duration(days: fixture));
    final resolved = start.add(const Duration(hours: 3));
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixture,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Serie A',
      country: 'Italia',
      matchDate: start,
      market: market,
      probability: probability,
      smartScore: 75,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: correct
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong,
      actualHomeGoals: correct ? 2 : 0,
      actualAwayGoals: correct ? 1 : 2,
      firstSeenAt: start.subtract(const Duration(hours: 2)),
      lastSeenAt: resolved,
      resolvedAt: resolved,
    );
  }

  test('MEI: non crea punteggi per 90 percento su 10 partite', () {
    final report = service.evaluate(
      records: [
        for (var i = 0; i < 10; i++)
          record(fixture: i + 1, correct: i < 9),
      ],
      asOf: asOf,
    );
    expect(report.segments.single.evidence.sampleSize, 10);
    expect(report.segments.single.score, isNull);
    expect(report.measurableSegments, 0);
    expect(report.segments.single.status, contains('100 incontri'));
  });

  test('MEI: 100 incontri distinti e 14 giornate abilita solo diagnostica', () {
    final report = service.evaluate(
      records: [
        for (var i = 0; i < 120; i++)
          record(fixture: i + 1, correct: i < 90),
      ],
      asOf: asOf,
    );
    final segment = report.segments.single;
    expect(segment.evidence.sampleSize, 120);
    expect(segment.evidence.distinctMatchDays, 120);
    expect(segment.usableForResearch, isTrue);
    expect(segment.score, greaterThan(0));
    expect(segment.score, lessThanOrEqualTo(100));
    expect(segment.status, contains('non validato live'));
  });

  test('MEI: sovrastima e Brier scadente non sono premiati', () {
    final report = service.evaluate(
      records: [
        for (var i = 0; i < 120; i++) ...[
          record(fixture: i + 1, correct: i < 90, market: 'GOAL',
              probability: 0.75),
          record(fixture: i + 1, correct: i < 90, market: 'NO GOAL',
              probability: 0.95),
        ],
      ],
      asOf: asOf,
    );
    final calibrated = report.segments.singleWhere(
      (s) => s.evidence.market == 'GOAL',
    );
    final overconfident = report.segments.singleWhere(
      (s) => s.evidence.market == 'NO GOAL',
    );
    expect(calibrated.evidence.sampleSize, overconfident.evidence.sampleSize);
    expect(calibrated.score!, greaterThan(overconfident.score!));
    expect(overconfident.overconfidencePenalty!, greaterThan(0));
    expect(overconfident.brierPenalty!, greaterThan(0));
  });

  test('MEI: le partite nello stesso giorno non superano il gate giorni', () {
    final report = service.evaluate(
      records: [
        for (var i = 0; i < 110; i++)
          record(
            fixture: i + 1,
            kickoff: DateTime.utc(2026, 9, 1)
                .add(Duration(days: i % 13)),
          ),
      ],
      asOf: asOf,
    );
    expect(report.segments.single.evidence.sampleSize, 110);
    expect(report.segments.single.evidence.distinctMatchDays, 13);
    expect(report.segments.single.score, isNull);
    expect(report.segments.single.status, contains('14 giornate'));
  });

  test('MEI: probabilita mancanti non producono un indice fuorviante', () {
    final report = service.evaluate(
      records: [
        for (var i = 0; i < 110; i++)
          record(fixture: i + 1,
              probability: i == 0 ? null : 0.75),
      ],
      asOf: asOf,
    );
    expect(report.segments.single.evidence.probabilitySampleSize, 109);
    expect(report.segments.single.score, isNull);
  });

  test('MEI: finestra mobile 12 mesi esclude il passato lontano', () {
    final old = [
      for (var i = 0; i < 130; i++)
        record(
          fixture: i + 1,
          kickoff: DateTime.utc(2024, 5, 1)
              .add(Duration(days: i)),
        ),
    ];
    final recent = [
      for (var i = 0; i < 10; i++)
        record(
          fixture: 1000 + i,
          kickoff: DateTime.utc(2026, 10, 1)
              .add(Duration(days: i)),
        ),
    ];
    final report = service.evaluate(records: [...old, ...recent], asOf: asOf);
    expect(report.uniqueEligibleRecords, 10);
    expect(report.segments.single.score, isNull);
  });

  test('MEI: i motori restano separati e lo score non muove pronostici', () {
    final report = service.evaluate(
      records: [
        for (var i = 0; i < 120; i++) ...[
          record(fixture: i + 1,
              engine: SmartBetAnalysisEngine.smartBet,
              correct: i < 96),
          record(fixture: i + 1,
              engine: SmartBetAnalysisEngine.diego,
              correct: i < 72),
        ],
      ],
      asOf: asOf,
    );
    expect(report.segments.length, 2);
    expect(report.measurableSegments, 2);
    final smart = report.segments.singleWhere(
      (s) => s.evidence.engine == SmartBetAnalysisEngine.smartBet,
    );
    final diego = report.segments.singleWhere(
      (s) => s.evidence.engine == SmartBetAnalysisEngine.diego,
    );
    expect(smart.score!, greaterThan(diego.score!));
    // Questo servizio restituisce solo indicatori, non AnalysisResult
    // e non modifica i record passati dal chiamante.
  });

  test('MEI: storici senza dati non sono valutati come 0% affidabili', () {
    final report = service.evaluate(records: [], asOf: asOf);
    expect(report.segments, isEmpty);
    expect(report.measurableSegments, 0);
  });
}
