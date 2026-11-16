import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/team_data_resolver.dart';

List<Map<String, Object?>> historicalFixtures(int teamId, int number) => [
  for (var i = 0; i < number; i++)
    {
      'fixture': {
        'id': 900000 + i,
        'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}T19:00:00Z',
        'status': {'short': 'FT'},
      },
      'league': {'round':'Round $i'},
      'teams': {
        'home': {'id': teamId, 'name': 'Test Team'},
        'away': {'id': 555, 'name': 'Opposition'},
      },
      'goals': {'home': 2, 'away': 1},
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B60: U21 league records allowed only for identified youth teams', () async {
    TeamDataResolver.clearCache();
    const teamId = 918331;
    var fixtureRequests = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/leagues')) {
        return http.Response(jsonEncode({'response': [
          {'league': {'id': 97231, 'name': 'Under 21 League',
            'type': 'League'}}
        ]}), 200);
      }
      if (req.url.path.endsWith('/fixtures')) {
        fixtureRequests++;
        return http.Response(jsonEncode({
          'response': historicalFixtures(teamId, 6),
        }), 200);
      }
      return http.Response('{"response":[]}', 200);
    });
    final resolver = TeamDataResolver(client: client);
    try {
      final date = DateTime.utc(2026, 11, 20);
      final adultMode = await resolver.resolveTeam(
        teamId: teamId, teamName:'U21 Team',
        referenceDate:date,
      );
      expect(adultMode, isNull);
      expect(fixtureRequests, 0);

      final youth = await resolver.resolveTeam(
        teamId: teamId, teamName:'U21 Team',
        referenceDate:date,
        allowYouthLeagues:true,
      );
      expect(youth, isNotNull);
      expect(youth!.matchesPlayed, 6);
      expect(youth.currentLeagueName, 'Under 21 League');
      expect(fixtureRequests, 1);
    } finally {
      resolver.dispose();
      TeamDataResolver.clearCache();
    }
  });

  test('B60: national fixtures use only real past matches of same competition', () async {
    TeamDataResolver.clearCache();
    const teamId=918332;
    const cup=77733;
    var fixtureRequests=0;
    final client=MockClient((req) async {
      if (req.url.path.endsWith('/leagues')) {
        return http.Response('{"response":[]}',200);
      }
      if (req.url.path.endsWith('/fixtures')) {
        fixtureRequests++;
        expect(req.url.queryParameters['league'], cup.toString());
        expect(req.url.queryParameters['season'], '2026');
        return http.Response(jsonEncode({
          'response': historicalFixtures(teamId,6),
        }),200);
      }
      return http.Response('{"response":[]}', 200);
    });
    final resolver=TeamDataResolver(client:client);
    try {
      final result=await resolver.resolveTeam(
        teamId:teamId,
        teamName:'National Team',
        referenceDate:DateTime.utc(2026,11,20),
        fallbackCompetitionId:cup,
        fallbackCompetitionName:'Nations League',
      );
      expect(result,isNotNull);
      expect(result!.matchesPlayed,6);
      expect(result.confidence, lessThan(0.60));
      expect(result.dataSource, contains('same-competition'));
      expect(result.leagueId,cup);
      expect(fixtureRequests,1);
    } finally {
      resolver.dispose();
      TeamDataResolver.clearCache();
    }
  });

  test('B60: national fallback refuses small and future contaminated samples', () async {
    TeamDataResolver.clearCache();
    const teamId=918333;
    final client=MockClient((req) async {
      if (req.url.path.endsWith('/leagues')) {
        return http.Response('{"response":[]}',200);
      }
      if (req.url.path.endsWith('/fixtures')) {
        final fixtures=historicalFixtures(teamId,3);
        fixtures.add({
          'fixture': {
            'id':999999,
            'date':'2026-11-25T18:00:00Z',
            'status': {'short':'FT'},
          },
          'teams':{
            'home': {'id':teamId,'name':'Test'},
            'away': {'id':555,'name':'Other'},
          },
          'goals':{'home':5,'away':0},
        });
        return http.Response(jsonEncode({'response':fixtures}),200);
      }
      return http.Response('{"response":[]}',200);
    });
    final resolver=TeamDataResolver(client:client);
    try {
      final result=await resolver.resolveTeam(
        teamId:teamId,
        teamName:'National Team',
        referenceDate:DateTime.utc(2026,11,20),
        fallbackCompetitionId:77734,
        fallbackCompetitionName:'Nations League',
      );
      expect(result,isNull);
    } finally {
      resolver.dispose();
      TeamDataResolver.clearCache();
    }
  });
}
