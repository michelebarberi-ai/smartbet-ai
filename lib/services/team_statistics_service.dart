import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class TeamStatistics {
  final int teamId;
  final String teamName;

  final int matchesPlayed;
  final int wins;
  final int draws;
  final int losses;

  final int goalsFor;
  final int goalsAgainst;

  final int homeWins;
  final int homeDraws;
  final int homeLosses;

  final int awayWins;
  final int awayDraws;
  final int awayLosses;

  const TeamStatistics({
    required this.teamId,
    required this.teamName,
    required this.matchesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.homeWins,
    required this.homeDraws,
    required this.homeLosses,
    required this.awayWins,
    required this.awayDraws,
    required this.awayLosses,
  });

  double get winRate {
    if (matchesPlayed == 0) {
      return 0;
    }

    return wins / matchesPlayed;
  }

  double get drawRate {
    if (matchesPlayed == 0) {
      return 0;
    }

    return draws / matchesPlayed;
  }

  double get lossRate {
    if (matchesPlayed == 0) {
      return 0;
    }

    return losses / matchesPlayed;
  }

  double get goalsPerMatch {
    if (matchesPlayed == 0) {
      return 0;
    }

    return goalsFor / matchesPlayed;
  }

  double get concededPerMatch {
    if (matchesPlayed == 0) {
      return 0;
    }

    return goalsAgainst / matchesPlayed;
  }

  double get goalDifference {
    return (goalsFor - goalsAgainst).toDouble();
  }
}

class TeamStatisticsService {
  final http.Client _client;

  TeamStatisticsService({http.Client? client})
    : _client = client ?? http.Client();

  Future<TeamStatistics?> getTeamStatistics({
    required int teamId,
    required int leagueId,
    required int season,
  }) async {
    if (teamId <= 0 || leagueId <= 0) {
      print('SMARTBET DEBUG: ID NON VALIDI');
      print('TEAM ID: $teamId');
      print('LEAGUE ID: $leagueId');
      print('SEASON: $season');

      return null;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/teams/statistics').replace(
      queryParameters: {
        'team': teamId.toString(),
        'league': leagueId.toString(),
        'season': season.toString(),
      },
    );

    print('========================================');
    print('SMARTBET DEBUG - TEAM STATISTICS');
    print('TEAM ID: $teamId');
    print('LEAGUE ID: $leagueId');
    print('SEASON: $season');
    print('URL: $uri');
    print('========================================');

    try {
      final response = await _client.get(uri);

      print('STATUS CODE: ${response.statusCode}');
      print('RESPONSE:');
      print(response.body);
      print('========================================');

      if (response.statusCode != 200) {
        print('SMARTBET DEBUG: STATUS CODE NON 200');

        return null;
      }

      final data = jsonDecode(response.body);

      if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
        print('SMARTBET API ERROR:');
        print(data['errors']);

        return null;
      }

      final responseData = data['response'];

      if (responseData is! Map<String, dynamic>) {
        print('SMARTBET DEBUG: response non valido');

        return null;
      }

      return _parseStatistics(responseData, teamId);
    } catch (e) {
      print('SMARTBET DEBUG EXCEPTION:');
      print(e);

      return null;
    }
  }

  TeamStatistics? _parseStatistics(Map<String, dynamic> data, int teamId) {
    final team = data['team'];
    final fixtures = data['fixtures'];
    final goals = data['goals'];

    if (team is! Map<String, dynamic>) {
      print('SMARTBET DEBUG: team non valido');

      return null;
    }

    if (fixtures is! Map<String, dynamic>) {
      print('SMARTBET DEBUG: fixtures non valido');

      return null;
    }

    if (goals is! Map<String, dynamic>) {
      print('SMARTBET DEBUG: goals non valido');

      return null;
    }

    final played = fixtures['played'];
    final wins = fixtures['wins'];
    final draws = fixtures['draws'];
    final losses = fixtures['loses'];

    final goalsFor = goals['for'];
    final goalsAgainst = goals['against'];

    final playedTotal = _extractInt(played);

    final winsTotal = _extractInt(wins);

    final drawsTotal = _extractInt(draws);

    final lossesTotal = _extractInt(losses);

    final goalsForTotal = _extractGoals(goalsFor);

    final goalsAgainstTotal = _extractGoals(goalsAgainst);

    final home = _extractVenueData(fixtures['home']);

    final away = _extractVenueData(fixtures['away']);

    print(
      'SMARTBET STATISTICHE LETTE: '
      '${team['name']} | '
      'Partite: $playedTotal | '
      'V: $winsTotal | '
      'X: $drawsTotal | '
      'S: $lossesTotal | '
      'GF: $goalsForTotal | '
      'GS: $goalsAgainstTotal',
    );

    return TeamStatistics(
      teamId: teamId,

      teamName: team['name']?.toString() ?? '',

      matchesPlayed: playedTotal,

      wins: winsTotal,

      draws: drawsTotal,

      losses: lossesTotal,

      goalsFor: goalsForTotal,

      goalsAgainst: goalsAgainstTotal,

      homeWins: home['wins'] ?? 0,

      homeDraws: home['draws'] ?? 0,

      homeLosses: home['losses'] ?? 0,

      awayWins: away['wins'] ?? 0,

      awayDraws: away['draws'] ?? 0,

      awayLosses: away['losses'] ?? 0,
    );
  }

  int _extractInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    if (value is Map<String, dynamic>) {
      return _extractInt(value['total']);
    }

    return 0;
  }

  int _extractGoals(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _extractInt(value['total']);
    }

    return _extractInt(value);
  }

  Map<String, int> _extractVenueData(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return {'wins': 0, 'draws': 0, 'losses': 0};
    }

    return {
      'wins': _extractInt(value['wins']),
      'draws': _extractInt(value['draws']),
      'losses': _extractInt(value['loses']),
    };
  }

  void dispose() {
    _client.close();
  }
}
