import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_comparison_store.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/smartbet_cross_market_audit_service.dart';

SmartBetAnalysisRecord record({
  required SmartBetAnalysisEngine engine,
  required String market,
  int fixtureId = 100,
  double probability = 0.8,
  SmartBetAnalysisStatus status = SmartBetAnalysisStatus.correct,
  bool qualified = true,
  bool prospective = true,
  bool resolved = true,
  int homeGoals = 2,
  int awayGoals = 1,
  DateTime? kickoff,
  bool latePrediction = false,
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
    actualHomeGoals: resolved ? homeGoals : null,
    actualAwayGoals: resolved ? awayGoals : null,
    firstSeenAt: latePrediction
        ? date.add(const Duration(hours: 1))
        : date.subtract(const Duration(hours: 24)),
    lastSeenAt: date.add(const Duration(hours: 24)),
    resolvedAt: resolved ? date.add(const Duration(hours: 24)) : null,
  );
}

SmartBetAnalysisComparisonLink link(
  SmartBetAnalysisRecord smartBet,
  SmartBetAnalysisRecord diego, {
  bool lateLink = false,
}) {
  final date = smartBet.matchDate;

  return SmartBetAnalysisComparisonLink(
    fixtureId: smartBet.fixtureId,
    smartBetRecordKey: smartBet.key,
    diegoRecordKey: diego.key,
    smartBetMarket: smartBet.market,
    diegoMarket: diego.market,
    sources: const [SmartBetAnalysisSource.analysis],
    firstSeenAt: lateLink
        ? date.add(const Duration(hours: 1))
        : date.subtract(const Duration(hours: 12)),
    lastSeenAt: date.add(const Duration(hours: 24)),
  );
}

void main() {
  const service = SmartBetCrossMarketAuditService();

  test('Goal e Over 2.5 corretti: Brier separato', () {
    final smart = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      probability: 0.8,
    );
    final diego = record(
      engine: SmartBetAnalysisEngine.diego,
      market: 'OVER 2.5',
      probability: 0.6,
    );

    final report = service.evaluate(
      records: [smart, diego],
      links: [link(smart, diego)],
    );

    final result = report.groups.single;
    expect(report.totalPairs, 1);
    expect(result.bothCorrect, 1);
    expect(result.smartBetBrier, closeTo(0.04, 1e-9));
    expect(result.diegoBrier, closeTo(0.16, 1e-9));
  });

  test('Esiti differenti sulla stessa partita', () {
    final smart = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      status: SmartBetAnalysisStatus.wrong,
      homeGoals: 1,
      awayGoals: 0,
    );
    final diego = record(
      engine: SmartBetAnalysisEngine.diego,
      market: 'UNDER 2.5',
      probability: 0.7,
      homeGoals: 1,
      awayGoals: 0,
    );

    final report = service.evaluate(
      records: [smart, diego],
      links: [link(smart, diego)],
    );

    final result = report.groups.single;
    expect(result.diegoOnlyCorrect, 1);
    expect(result.smartBetAccuracy, 0);
    expect(result.diegoAccuracy, 1);
  });

  test('Mercato identico escluso: gestito dal confronto omogeneo', () {
    final smart = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
    );
    final diego = record(engine: SmartBetAnalysisEngine.diego, market: 'GOAL');

    final report = service.evaluate(
      records: [smart, diego],
      links: [link(smart, diego)],
    );

    expect(report.totalPairs, 0);
    expect(report.excludedLinks, 1);
  });

  test('Diego non qualificato escluso', () {
    final smart = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
    );
    final diego = record(
      engine: SmartBetAnalysisEngine.diego,
      market: 'OVER 2.5',
      qualified: false,
    );

    final report = service.evaluate(
      records: [smart, diego],
      links: [link(smart, diego)],
    );

    expect(report.totalPairs, 0);
  });

  test('Registrazione tardiva o risultato assente esclusi', () {
    final smart = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
    );
    final diego = record(
      engine: SmartBetAnalysisEngine.diego,
      market: 'OVER 2.5',
    );

    final late = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
      fixtureId: 101,
      latePrediction: true,
    );
    final other = record(
      engine: SmartBetAnalysisEngine.diego,
      market: 'OVER 2.5',
      fixtureId: 101,
    );

    final report = service.evaluate(
      records: [smart, diego, late, other],
      links: [link(smart, diego, lateLink: true), link(late, other)],
    );

    expect(report.totalPairs, 0);
    expect(report.excludedLinks, 2);
  });

  test('Risultati incoerenti non vengono confrontati', () {
    final smart = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
    );
    final diego = record(
      engine: SmartBetAnalysisEngine.diego,
      market: 'OVER 2.5',
      homeGoals: 1,
      awayGoals: 0,
    );

    final report = service.evaluate(
      records: [smart, diego],
      links: [link(smart, diego)],
    );

    expect(report.totalPairs, 0);
  });

  test('Duplicati non vengono conteggiati due volte', () {
    final smart = record(
      engine: SmartBetAnalysisEngine.smartBet,
      market: 'GOAL',
    );
    final diego = record(
      engine: SmartBetAnalysisEngine.diego,
      market: 'OVER 2.5',
    );
    final pair = link(smart, diego);

    final report = service.evaluate(
      records: [smart, diego, smart],
      links: [pair, pair],
    );

    expect(report.totalPairs, 1);
    expect(report.distinctFixtures, 1);
    expect(report.excludedLinks, 1);
  });
}
