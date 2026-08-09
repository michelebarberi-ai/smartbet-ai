import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class HistoricalTeamData {
  final int originalTeamId;
  final String originalTeamName;

  final int season;
  final int leagueId;
  final String leagueName;

  final int matchesPlayed;
  final int wins;
  final int draws;
  final int losses;

  final int goalsFor;
  final int goalsAgainst;

  final int homeMatches;
  final int homeWins;
  final int homeDraws;
  final int homeLosses;

  final int awayMatches;
  final int awayWins;
  final int awayDraws;
  final int awayLosses;

  const HistoricalTeamData({
    required this.originalTeamId,
    required this.originalTeamName,
    required this.season,
    required this.leagueId,
    required this.leagueName,
    required this.matchesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.homeMatches,
    required this.homeWins,
    required this.homeDraws,
    required this.homeLosses,
    required this.awayMatches,
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

  double get goalDifferencePerMatch {
    if (matchesPlayed == 0) {
      return 0;
    }

    return (goalsFor - goalsAgainst) / matchesPlayed;
  }

  double get homeWinRate {
    if (homeMatches == 0) {
      return 0;
    }

    return homeWins / homeMatches;
  }

  double get awayWinRate {
    if (awayMatches == 0) {
      return 0;
    }

    return awayWins / awayMatches;
  }
}

class HistoricalTeamService {
  final http.Client _client;

  HistoricalTeamService({http.Client? client})
    : _client = client ?? http.Client();

  // ============================================================
  // CACHE
  // ============================================================

  static final Map<String, HistoricalTeamData?> _cache = {};

  // ============================================================
  // RECUPERO STORICO
  // ============================================================

  Future<HistoricalTeamData?> getHistoricalData({
    required int teamId,
    required String teamName,
    required int season,
    required int leagueId,
    String leagueName = '',
  }) async {
    if (teamId <= 0 || season <= 0 || leagueId <= 0) {
      print('SMARTBET HISTORICAL: parametri non validi');

      return null;
    }

    final cacheKey = '$teamId-$season-$leagueId';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    print('');
    print('========================================');
    print('SMARTBET - HISTORICAL DATA');
    print('Squadra: $teamName');
    print('Team ID: $teamId');
    print('Stagione: $season');
    print('League ID: $leagueId');
    print('========================================');

    final uri = Uri.parse('${ApiConfig.baseUrl}/fixtures').replace(
      queryParameters: {
        'team': teamId.toString(),
        'season': season.toString(),
        'league': leagueId.toString(),
      },
    );

    try {
      final response = await _client.get(uri, headers: _headers);

      print(
        'SMARTBET HISTORICAL STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        _cache[cacheKey] = null;
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        _cache[cacheKey] = null;
        return null;
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('HISTORICAL API ERROR:');
        print(errors);

        _cache[cacheKey] = null;
        return null;
      }

      final fixtures = decoded['response'];

      if (fixtures is! List || fixtures.isEmpty) {
        print(
          'SMARTBET HISTORICAL: '
          'nessuna partita trovata',
        );

        _cache[cacheKey] = null;
        return null;
      }

      final data = _calculateStatistics(
        fixtures,
        teamId: teamId,
        teamName: teamName,
        season: season,
        leagueId: leagueId,
        leagueName: leagueName,
      );

      _cache[cacheKey] = data;

      return data;
    } catch (e) {
      print('SMARTBET HISTORICAL EXCEPTION: $e');

      _cache[cacheKey] = null;

      return null;
    }
  }

  // ============================================================
  // CALCOLO STATISTICHE
  // ============================================================

  HistoricalTeamData? _calculateStatistics(
    List<dynamic> fixtures, {
    required int teamId,
    required String teamName,
    required int season,
    required int leagueId,
    required String leagueName,
  }) {
    int matchesPlayed = 0;

    int wins = 0;
    int draws = 0;
    int losses = 0;

    int goalsFor = 0;
    int goalsAgainst = 0;

    int homeMatches = 0;
    int homeWins = 0;
    int homeDraws = 0;
    int homeLosses = 0;

    int awayMatches = 0;
    int awayWins = 0;
    int awayDraws = 0;
    int awayLosses = 0;

    for (final item in fixtures) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final fixture = item['fixture'];
      final teams = item['teams'];
      final goals = item['goals'];

      if (fixture is! Map<String, dynamic>) {
        continue;
      }

      if (teams is! Map<String, dynamic>) {
        continue;
      }

      if (goals is! Map<String, dynamic>) {
        continue;
      }

      final home = teams['home'];
      final away = teams['away'];

      if (home is! Map<String, dynamic> || away is! Map<String, dynamic>) {
        continue;
      }

      final homeId = _toInt(home['id']);
      final awayId = _toInt(away['id']);

      if (homeId != teamId && awayId != teamId) {
        continue;
      }

      // --------------------------------------------------------
      // RISULTATO
      // --------------------------------------------------------

      final homeGoals = _toInt(goals['home']);

      final awayGoals = _toInt(goals['away']);

      matchesPlayed++;

      // --------------------------------------------------------
      // CASA
      // --------------------------------------------------------

      if (homeId == teamId) {
        homeMatches++;

        goalsFor += homeGoals;
        goalsAgainst += awayGoals;

        if (homeGoals > awayGoals) {
          wins++;
          homeWins++;
        } else if (homeGoals == awayGoals) {
          draws++;
          homeDraws++;
        } else {
          losses++;
          homeLosses++;
        }
      }
      // --------------------------------------------------------
      // TRASFERTA
      // --------------------------------------------------------
      else if (awayId == teamId) {
        awayMatches++;

        goalsFor += awayGoals;
        goalsAgainst += homeGoals;

        if (awayGoals > homeGoals) {
          wins++;
          awayWins++;
        } else if (awayGoals == homeGoals) {
          draws++;
          awayDraws++;
        } else {
          losses++;
          awayLosses++;
        }
      }
    }

    if (matchesPlayed == 0) {
      return null;
    }

    print('');
    print('SMARTBET HISTORICAL RISULTATO');
    print('Squadra: $teamName');
    print('Partite: $matchesPlayed');
    print('Vittorie: $wins');
    print('Pareggi: $draws');
    print('Sconfitte: $losses');
    print('Gol fatti: $goalsFor');
    print('Gol subiti: $goalsAgainst');
    print('Casa: $homeWins V / $homeDraws X / $homeLosses S');
    print('Trasferta: $awayWins V / $awayDraws X / $awayLosses S');

    return HistoricalTeamData(
      originalTeamId: teamId,
      originalTeamName: teamName,
      season: season,
      leagueId: leagueId,
      leagueName: leagueName,
      matchesPlayed: matchesPlayed,
      wins: wins,
      draws: draws,
      losses: losses,
      goalsFor: goalsFor,
      goalsAgainst: goalsAgainst,
      homeMatches: homeMatches,
      homeWins: homeWins,
      homeDraws: homeDraws,
      homeLosses: homeLosses,
      awayMatches: awayMatches,
      awayWins: awayWins,
      awayDraws: awayDraws,
      awayLosses: awayLosses,
    );
  }

  // ============================================================
  // HEADERS
  // ============================================================

  Map<String, String> get _headers {
    return {'x-apisports-key': ApiConfig.apiKey, 'Accept': 'application/json'};
  }

  // ============================================================
  // CONVERSIONE
  // ============================================================

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  // ============================================================
  // CACHE
  // ============================================================

  static void clearCache() {
    _cache.clear();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _client.close();
  }
}
