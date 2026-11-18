import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/goalvdline_third_brain_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_third_brain_own_input_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_third_brain_history_capture_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';
import 'package:smartbet_ai_new/services/team_form_service.dart';

void main() {
  const service = GoalVdLineThirdBrainOwnInputService();
  final now = DateTime.utc(2026, 11, 18, 9);
  final kickoff = DateTime.utc(2026, 12, 15, 20, 45);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TeamFormService.clearCache();
  });

  MatchModel match() => MatchModel(
    fixtureId: 997,
    homeTeamId: 11,
    awayTeamId: 22,
    homeTeam: 'Juventus',
    awayTeam: 'Parma',
    league: 'Serie A',
    leagueId: 135,
    country: 'Italy',
    countryCode: 'IT',
    date: kickoff.toIso8601String(),
    leagueType: 'domestic',
    isEuropeanCup: false,
    isFriendly: false,
    isNational: false,
    aiWeight: 0.70,
    smartScore: 0,
    homeWin: 0,
    draw: 0,
    awayWin: 0,
    valueBet: '',
    odd: 0,
  );

  Map<String, dynamic> game({
    required int id,
    required DateTime date,
    required int home,
    required int away,
    int gh = 2,
    int ga = 1,
    String status = 'FT',
  }) => {
    'fixture': {
      'id': id, 'date': date.toUtc().toIso8601String(),
      'status': {'short': status},
    },
    'teams': {
      'home': {'id': home, 'name': 'Casa'},
      'away': {'id': away, 'name': 'Ospite'},
    },
    'goals': {'home': gh, 'away': ga},
  };

  List<dynamic> homeGames() => [
    for (var i = 0; i < 4; i++)
      game(id: 100 + i, date: now.subtract(Duration(days: 8 + i * 7)),
        home: 11, away: 40 + i, gh: 2 + i % 2, ga: 1),
  ];

  List<dynamic> awayGames() => [
    for (var i = 0; i < 4; i++)
      game(id: 200 + i, date: now.subtract(Duration(days: 7 + i * 7)),
        home: 60 + i, away: 22, gh: 1, ga: i % 2),
  ];

  AnalysisResult smartBet() => const AnalysisResult(
    smartScore: 86,
    dataConfidence: 90,
    homeProbability: 86,
    drawProbability: 9,
    awayProbability: 5,
    expectedHomeGoals: 4.5,
    expectedAwayGoals: 0.2,
    prediction: '1',
    risk: 'LOW',
    valueBet: '',
    explanation: 'Analisi di prova',
  );

  test('modello autonomo calcola xG da risultati grezzi, non da SmartBet', () {
    final own = service.fromFixtureHistory(
      match: match(), observedAt: now,
      homeHistory: homeGames(), awayHistory: awayGames(),
    );
    expect(own, isNotNull);
    expect(own!.homeVenueMatches, 4);
    expect(own.awayVenueMatches, 4);
    expect(own.source, contains('API-Football'));
    expect(own.modelVersion, 'third-brain-venue-scorelines-v1');
    expect(own.expectedHomeGoals, greaterThan(own.expectedAwayGoals));
    expect(own.expectedHomeGoals, lessThan(4.5));
    final result = const GoalVdLineThirdBrainService().evaluate(
      smartBet: smartBet(), ownInput: own,
    )!;
    expect(result.inputSource, own.source);
    expect(result.modelVersion, own.modelVersion);
    expect(result.homeExpectedGoals, own.expectedHomeGoals);
    expect(result.awayExpectedGoals, own.expectedAwayGoals);
    expect(result.sharesDiegoInputs, isFalse);
  });

  test('solo FT prima osservazione; niente dati futuri, status NS e doppi', () {
    final home = [
      ...homeGames().take(2),
      game(id: 500, date: now.add(const Duration(days: 1)),
        home: 11, away: 88, gh: 20, ga: 0),
      game(id: 501, date: now.subtract(const Duration(days: 3)),
        home: 11, away: 88, gh: 20, ga: 0, status: 'NS'),
      homeGames()[0],
    ];
    expect(service.fromFixtureHistory(
      match: match(), observedAt: now,
      homeHistory: home, awayHistory: awayGames(),
    ), isNull);

    expect(service.fromFixtureHistory(
      match: match(), observedAt: now,
      homeHistory: homeGames(), awayHistory: awayGames(),
    ), isNotNull);
  });

  test('campione di soli due match in casa non produce finta affidabilita', () {
    expect(service.fromFixtureHistory(
      match: match(), observedAt: now,
      homeHistory: homeGames().take(2).toList(),
      awayHistory: awayGames(),
    ), isNull);
    expect(service.fromFixtureHistory(
      match: match(), observedAt: kickoff.add(const Duration(minutes: 1)),
      homeHistory: homeGames(), awayHistory: awayGames(),
    ), isNull);
  });

  test('cache delle fixture riutilizzata senza richieste API aggiuntive', () async {
    final client = MockClient((req) async {
      final teamId = int.parse(req.url.queryParameters['team']!);
      final data = teamId == 11 ? homeGames() : awayGames();
      return http.Response(jsonEncode({'errors': {}, 'response': data}), 200);
    });
    final form = TeamFormService(client: client);
    expect((await form.getTeamForm(teamId: 11))?.matchesPlayed, 4);
    expect((await form.getTeamForm(teamId: 22))?.matchesPlayed, 4);

    final own = service.fromCachedFixtureHistory(
      match: match(), observedAt: now,
    );
    expect(own, isNotNull);
    expect(own!.homeVenueMatches, 4);
    expect(own.awayVenueMatches, 4);
    form.dispose();
  });

  test('archivio prospettico congela origine, versione e probabilita', () async {
    final own = service.fromFixtureHistory(
      match: match(), observedAt: now,
      homeHistory: homeGames(), awayHistory: awayGames(),
    )!;
    final store = SmartBetAnalysisHistoryStore();
    final captured = await GoalVdLineThirdBrainHistoryCaptureService(store: store)
        .capture(
          match: match(),
          smartBet: smartBet(),
          ownInput: own,
          source: SmartBetAnalysisSource.analysis,
          recordedAt: now,
        );
    expect(captured, hasLength(5));
    expect(captured.every((r) => r.inputSource == own.source &&
      r.modelVersion == own.modelVersion &&
      r.prospectiveEligible && r.quotedOdd == null), isTrue);
    final later = await GoalVdLineThirdBrainHistoryCaptureService(store: store)
        .capture(
          match: match(),
          smartBet: smartBet(),
          source: SmartBetAnalysisSource.combinations,
          recordedAt: now.add(const Duration(hours: 1)),
        );
    expect(later, hasLength(5));
    expect(store.records, hasLength(5));
    expect(store.records.first.firstSeenAt, now);
    expect(store.records.first.modelVersion, own.modelVersion);
  });
}
