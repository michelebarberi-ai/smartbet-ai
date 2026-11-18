import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_three_engine_paired_comparison_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_three_engine_paired_comparison_panel.dart';

void main() {
  const evaluator = GoalVdLineThreeEnginePairedComparisonService();
  final cutoff = DateTime.utc(2026, 11, 18, 17);

  SmartBetAnalysisRecord record({
    required int fixture,
    required SmartBetAnalysisEngine engine,
    required double? probability,
    bool hit = true,
    String market = 'GOAL',
    String country = 'Italia',
    String league = 'Serie A',
    String source = 'Risultati FT API-Football',
    String version = 'third-brain-venue-scorelines-v1',
    DateTime? kickoff,
    DateTime? firstSeen,
    DateTime? known,
    SmartBetAnalysisStatus? status,
  }) {
    final date = kickoff ?? DateTime.utc(2026, 9, 1).add(
      Duration(days: fixture % 60),
    );
    final scoredHome = hit ? 2 : 1;
    final scoredAway = hit ? 1 : 0;
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixture,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: league,
      country: country,
      matchDate: date,
      market: market,
      probability: probability,
      smartScore: null,
      confidence: null,
      classification: null,
      qualified: null,
      inputSource: engine == SmartBetAnalysisEngine.thirdBrain ? source : null,
      modelVersion: engine == SmartBetAnalysisEngine.thirdBrain ? version : null,
      sources: const [SmartBetAnalysisSource.analysis],
      prospectiveEligible: true,
      status: status ?? (hit
          ? SmartBetAnalysisStatus.correct
          : SmartBetAnalysisStatus.wrong),
      actualHomeGoals: scoredHome,
      actualAwayGoals: scoredAway,
      firstSeenAt: firstSeen ?? date.subtract(const Duration(hours: 5)),
      lastSeenAt: date.add(const Duration(hours: 3)),
      resolvedAt: known ?? date.add(const Duration(hours: 3)),
    );
  }

  List<SmartBetAnalysisRecord> trio(
    int fixture, {
    bool hit = true,
    String market = 'GOAL',
    double smart = 0.75,
    double diego = 0.95,
    double third = 0.60,
    String source = 'Risultati FT API-Football',
    String version = 'third-brain-venue-scorelines-v1',
    DateTime? kickoff,
  }) => [
    record(fixture: fixture, engine: SmartBetAnalysisEngine.smartBet,
      probability: smart, hit: hit, market: market, kickoff: kickoff),
    record(fixture: fixture, engine: SmartBetAnalysisEngine.diego,
      probability: diego, hit: hit, market: market, kickoff: kickoff),
    record(fixture: fixture, engine: SmartBetAnalysisEngine.thirdBrain,
      probability: third, hit: hit, market: market,
      source: source, version: version, kickoff: kickoff),
  ];

  test('tre motori: campione esattamente allineato e metriche non identiche', () {
    final report = evaluator.evaluate(
      records: [
        for (var i = 1; i <= 40; i++)
          ...trio(i, hit: i <= 30),
      ],
      asOf: cutoff,
    );
    expect(report.pairedFixtureMarkets, 40);
    expect(report.segments, hasLength(1));
    final segment = report.segments.single;
    expect(segment.fixtureCount, 40);
    expect(segment.distinctMatchDays, 40);
    expect(segment.sufficientEvidence, isFalse);
    final smart = segment.forEngine(SmartBetAnalysisEngine.smartBet);
    final diego = segment.forEngine(SmartBetAnalysisEngine.diego);
    final third = segment.forEngine(SmartBetAnalysisEngine.thirdBrain);
    expect(smart.correct, 30);
    expect(diego.correct, 30);
    expect(third.correct, 30);
    expect(smart.accuracyPercent, 75);
    expect(diego.accuracyPercent, 75);
    expect(third.accuracyPercent, 75);
    expect(smart.brierScore, lessThan(diego.brierScore));
    expect(smart.brierScore, lessThan(third.brierScore));
    expect(smart.logLoss, lessThan(diego.logLoss));
    expect(smart.calibrationGapPoints, closeTo(0, 1e-10));
    expect(diego.calibrationGapPoints, lessThan(0));
    expect(segment.canChangePredictions, isFalse);
  });

  test('nessuna terna quando un cervello manca o i mercati sono diversi', () {
    final records = [
      record(fixture: 201, engine: SmartBetAnalysisEngine.smartBet,
        probability: 0.75),
      record(fixture: 201, engine: SmartBetAnalysisEngine.diego,
        probability: 0.70),
      record(fixture: 202, engine: SmartBetAnalysisEngine.smartBet,
        probability: 0.75),
      record(fixture: 202, engine: SmartBetAnalysisEngine.diego,
        probability: 0.70, market: 'OVER 1.5'),
      record(fixture: 202, engine: SmartBetAnalysisEngine.thirdBrain,
        probability: 0.65),
    ];
    final report = evaluator.evaluate(records: records, asOf: cutoff);
    expect(report.pairedFixtureMarkets, 0);
    expect(report.segments, isEmpty);
  });

  test('no leakage: rigetta registrazioni tardive e risultati noti prima', () {
    final date = DateTime.utc(2026, 10, 12, 20);
    final late = [
      record(fixture: 301, engine: SmartBetAnalysisEngine.smartBet,
        probability: 0.75, kickoff: date,
        firstSeen: date.subtract(const Duration(seconds: 30))),
      record(fixture: 301, engine: SmartBetAnalysisEngine.diego,
        probability: 0.75, kickoff: date),
      record(fixture: 301, engine: SmartBetAnalysisEngine.thirdBrain,
        probability: 0.75, kickoff: date),
    ];
    final prematurelyKnown = [
      record(fixture: 302, engine: SmartBetAnalysisEngine.smartBet,
        probability: 0.75, kickoff: date,
        known: date.subtract(const Duration(minutes: 2))),
      record(fixture: 302, engine: SmartBetAnalysisEngine.diego,
        probability: 0.75, kickoff: date),
      record(fixture: 302, engine: SmartBetAnalysisEngine.thirdBrain,
        probability: 0.75, kickoff: date),
    ];
    expect(evaluator.evaluate(
      records: [...late, ...prematurelyKnown], asOf: cutoff,
    ).pairedFixtureMarkets, 0);
  });

  test('esiti o provenienza per motore in conflitto non vengono confrontati', () {
    final badResult = [
      ...trio(303),
      record(fixture: 303, engine: SmartBetAnalysisEngine.diego,
        probability: 0.70, hit: false),
    ];
    final badLeague = [
      ...trio(304),
      record(fixture: 304, engine: SmartBetAnalysisEngine.diego,
        probability: 0.75, league: 'Serie B'),
    ];
    final report = evaluator.evaluate(
      records: [...badResult, ...badLeague], asOf: cutoff,
    );
    expect(report.pairedFixtureMarkets, 0);
    expect(report.conflictingFixtureMarkets, 2);
  });

  test('duplicati identici non contano due volte, probabilità false escluse', () {
    final match = trio(305);
    final report = evaluator.evaluate(records: [
      ...match,
      match[0],
      ...trio(306),
      record(fixture: 306, engine: SmartBetAnalysisEngine.diego,
        probability: double.nan),
    ], asOf: cutoff);
    expect(report.pairedFixtureMarkets, 1);
    expect(report.segments.single.fixtureCount, 1);
  });

  test('terzo motore con sorgenti/versioni diverse resta in segmenti distinti', () {
    final report = evaluator.evaluate(
      records: [
        ...trio(307, source: 'Risultati FT', version: 'v1'),
        ...trio(308, source: 'SmartBet AI', version: 'legacy'),
      ],
      asOf: cutoff,
    );
    expect(report.pairedFixtureMarkets, 2);
    expect(report.segments, hasLength(2));
    expect(report.segments.every((s) => s.fixtureCount == 1), isTrue);
    expect(report.segments.map((s) => s.thirdInputSource).toSet().length, 2);
  });

  test('gate 100 partite e 14 giornate: solo ricerca, mai modifica live', () {
    final report = evaluator.evaluate(records: [
      for (var i = 1; i <= 110; i++) ...trio(1000 + i,
        kickoff: DateTime.utc(2026, 10, 1).add(
          Duration(days: i % 13),
        )),
    ], asOf: cutoff);
    expect(report.segments.single.fixtureCount, 110);
    expect(report.segments.single.distinctMatchDays, 13);
    expect(report.segments.single.sufficientEvidence, isFalse);

    final research = evaluator.evaluate(records: [
      for (var i = 1; i <= 105; i++) ...trio(2000 + i,
        kickoff: DateTime.utc(2026, 8, 1).add(
          Duration(days: i % 30),
        )),
    ], asOf: cutoff);
    expect(research.segments.single.sufficientEvidence, isTrue);
    expect(research.researchReadySegments, 1);
    expect(research.segments.single.canChangePredictions, isFalse);
  });

  test('finestra 12 mesi e risultati successivi al cutoff non entrano', () {
    final old = trio(4000, kickoff: DateTime.utc(2024, 10, 10));
    final future = trio(4001, kickoff: DateTime.utc(2026, 11, 25));
    final recent = trio(4002, kickoff: DateTime.utc(2026, 10, 25));
    final report = evaluator.evaluate(
      records: [...old, ...future, ...recent], asOf: cutoff,
    );
    expect(report.pairedFixtureMarkets, 1);
  });

  testWidgets('pannello non inventa dati in assenza di terne', (tester) async {
    final report = evaluator.evaluate(records: [], asOf: cutoff);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineThreeEnginePairedComparisonPanel(report: report),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('three-engine-paired-panel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('three-engine-no-paired-data')), findsOneWidget);
    expect(find.textContaining('Nessuna terna verificata'), findsOneWidget);
  });
}
