import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/dual_engine_analysis_service.dart';
import 'package:smartbet_ai_new/services/smartbet_ai_service.dart';
import 'package:smartbet_ai_new/services/team_data_resolver.dart';
import 'package:smartbet_ai_new/widgets/dual_engine_summary.dart';

class _NoDossierDiego extends Fake implements DiegoAiService {
  @override
  Future<DiegoAiAnalysis?> analyze(
    MatchModel match, {
    int simulations = 20000,
  }) async => null;
}

class _UnusedSmartBet extends Fake implements SmartBetAiService {}

MatchModel match({int homeId = 201, int awayId = 202, String? date}) =>
    MatchModel(
      fixtureId: 123789,
      homeTeamId: homeId,
      awayTeamId: awayId,
      homeTeam: 'Club Casa',
      awayTeam: 'Club Ospite',
      league: 'Serie C',
      leagueId: 138,
      country: 'Italia',
      countryCode: 'IT',
      date: date ?? '2026-11-20T18:00:00Z',
      leagueType: 'domestic',
      isEuropeanCup: false,
      isFriendly: false,
      isNational: false,
      aiWeight: 0.9,
      smartScore: 80,
      homeWin: 60,
      draw: 25,
      awayWin: 15,
      valueBet: '',
      odd: 0,
    );

AnalysisResult smart() => AnalysisResult(
      smartScore: 75,
      sportsAuditStatus: 'NOT_RUN',
      homeProbability: 60,
      drawProbability: 25,
      awayProbability: 15,
      prediction: '1',
      valueBet: '',
      risk: 'MEDIO',
      explanation: 'Forecast sportivo preliminare',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B60: missing dossier produces explicit data reason, no synthetic Diego',
      () async {
    final service = DualEngineAnalysisService(
      smartBetService: _UnusedSmartBet(),
      diegoService: _NoDossierDiego(),
    );
    final result = await service.attachDiego(
      match: match(),
      smartBet: smart(),
      smartBetMarket: 'X',
      smartBetProbability: 25,
    );
    expect(result.diego, isNull);
    expect(result.comparison.diegoMarket, 'N/D');
    expect(result.comparison.diegoProbability, isNull);
    expect(result.diegoUnavailableReason, contains('Dati storici'));
  });

  test('B60: missing team IDs are distinguished from missing stats', () async {
    final service = DualEngineAnalysisService(
      smartBetService: _UnusedSmartBet(),
      diegoService: _NoDossierDiego(),
    );
    final result = await service.attachDiego(
      match: match(homeId: 0),
      smartBet: smart(),
      smartBetMarket: '1',
      smartBetProbability: 60,
    );
    expect(result.diegoUnavailableReason, contains('identificativi'));
  });

  test('B60: missing kickoff is distinguished from sports value', () async {
    final service = DualEngineAnalysisService(
      smartBetService: _UnusedSmartBet(),
      diegoService: _NoDossierDiego(),
    );
    final result = await service.attachDiego(
      match: match(date: 'invalid'),
      smartBet: smart(),
      smartBetMarket: 'X',
      smartBetProbability: 25,
    );
    expect(result.diegoUnavailableReason, contains('Data'));
  });

  testWidgets('B60: user sees the reason for Diego N/D, not a false guess',
      (tester) async {
    final service = DualEngineAnalysisService(
      smartBetService: _UnusedSmartBet(),
      diegoService: _NoDossierDiego(),
    );
    final result = await service.attachDiego(
      match: match(),
      smartBet: smart(),
      smartBetMarket: 'X',
      smartBetProbability: 25,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: DualEngineSummary(analysis: result)),
      ),
    ));
    expect(find.byKey(const Key('b60-diego-data-readiness')), findsOneWidget);
    expect(find.textContaining('DIEGO AI · MOTIVO N/D'), findsOneWidget);
    expect(find.textContaining('Dati storici'), findsOneWidget);
    expect(find.textContaining('AUDITOR SPORTIVO NON ESEGUITO'), findsOneWidget);
  });

  test('B60: failed team source is short cached but retries after cache reset',
      () async {
    TeamDataResolver.clearCache();
    var calls = 0;
    final resolver = TeamDataResolver(client: MockClient((_) async {
      calls++;
      return http.Response('{"response":[]}', 200);
    }));
    try {
      final first = await resolver.resolveTeam(
        teamId: 987641,
        teamName: 'Senza dati B60',
        referenceDate: DateTime.utc(2026, 11, 20),
      );
      expect(first, isNull);
      final afterFirst = calls;
      expect(afterFirst, greaterThan(0));
      final second = await resolver.resolveTeam(
        teamId: 987641,
        teamName: 'Senza dati B60',
        referenceDate: DateTime.utc(2026, 11, 20),
      );
      expect(second, isNull);
      expect(calls, afterFirst);
      TeamDataResolver.clearCache();
      final retried = await resolver.resolveTeam(
        teamId: 987641,
        teamName: 'Senza dati B60',
        referenceDate: DateTime.utc(2026, 11, 20),
      );
      expect(retried, isNull);
      expect(calls, greaterThan(afterFirst));
    } finally {
      resolver.dispose();
      TeamDataResolver.clearCache();
    }
  });
}
