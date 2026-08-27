import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/team_profile.dart';

class TeamProfileService {
  final http.Client _client;

  TeamProfileService({http.Client? client}) : _client = client ?? http.Client();

  // ============================================================
  // CACHE
  // ============================================================

  static final Map<String, TeamProfile?> _cache = {};

  // ============================================================
  // PROFILO BASE DELLA SQUADRA
  // ============================================================

  Future<TeamProfile?> getTeamProfile({
    required int teamId,
    required int leagueId,
    required int season,
    String country = '',
    String league = '',
  }) async {
    if (teamId <= 0) {
      print('SMARTBET PROFILE: teamId non valido');
      return null;
    }

    final cacheKey = '$teamId-$leagueId-$season';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    TeamProfile profile = TeamProfile(
      teamId: teamId,
      teamName: '',
      country: country,
      league: league,
      dataConfidence: 10,
    );

    // ==========================================================
    // DATI SQUADRA
    // ==========================================================

    final teamData = await _getTeam(teamId);

    if (teamData != null) {
      profile = TeamProfile(
        teamId: teamId,
        teamName: teamData['name']?.toString() ?? '',
        country: _extractCountry(teamData, country),
        league: league,
        strength: 50,
        squadStrength: 50,
        attackStrength: 50,
        defenseStrength: 50,
        form: 50,
        homeStrength: 50,
        awayStrength: 50,
        historicalStrength: 50,
        leagueStrength: 50,
        injuredPlayers: 0,
        suspendedPlayers: 0,
        unavailablePlayers: 0,
        dataConfidence: 20,
      );
    }

    // ==========================================================
    // STATISTICHE STAGIONE
    // ==========================================================

    final statistics = await _getTeamStatistics(
      teamId: teamId,
      leagueId: leagueId,
      season: season,
    );

    if (statistics != null) {
      profile = _applyStatistics(profile, statistics);
    }

    // ==========================================================
    // ROSA
    // ==========================================================

    final squad = await _getSquad(teamId);

    if (squad != null) {
      profile = _applySquad(profile, squad);
    }

    // ==========================================================
    // INFORTUNI / SQUALIFICHE
    // ==========================================================

    final unavailable = await _getUnavailablePlayers(
      teamId: teamId,
      season: season,
    );

    if (unavailable != null) {
      profile = _applyUnavailablePlayers(profile, unavailable);
    }

    _cache[cacheKey] = profile;

    return profile;
  }

  // ============================================================
  // TEAM
  // ============================================================

  Future<Map<String, dynamic>?> _getTeam(int teamId) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/teams',
    ).replace(queryParameters: {'id': teamId.toString()});

    try {
      final response = await _client.get(uri);

      print(
        'SMARTBET PROFILE /teams '
        '$teamId → ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        return null;
      }

      final responseData = data['response'];

      if (responseData is! List || responseData.isEmpty) {
        return null;
      }

      final first = responseData.first;

      if (first is! Map<String, dynamic>) {
        return null;
      }

      final team = first['team'];

      if (team is! Map<String, dynamic>) {
        return null;
      }

      return team;
    } catch (e) {
      print('SMARTBET PROFILE /teams ERROR: $e');

      return null;
    }
  }

  // ============================================================
  // STATISTICHE SQUADRA
  // ============================================================

  Future<Map<String, dynamic>?> _getTeamStatistics({
    required int teamId,
    required int leagueId,
    required int season,
  }) async {
    if (leagueId <= 0) {
      return null;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/teams/statistics').replace(
      queryParameters: {
        'team': teamId.toString(),
        'league': leagueId.toString(),
        'season': season.toString(),
      },
    );

    try {
      final response = await _client.get(uri);

      print(
        'SMARTBET PROFILE /teams/statistics '
        '$teamId → ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        return null;
      }

      final responseData = data['response'];

      if (responseData is! Map<String, dynamic>) {
        return null;
      }

      return responseData;
    } catch (e) {
      print('SMARTBET PROFILE /teams/statistics ERROR: $e');

      return null;
    }
  }

  // ============================================================
  // ROSA
  // ============================================================

  Future<List<Map<String, dynamic>>?> _getSquad(int teamId) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/players/squads',
    ).replace(queryParameters: {'team': teamId.toString()});

    try {
      final response = await _client.get(uri);

      print(
        'SMARTBET PROFILE /players/squads '
        '$teamId → ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        return null;
      }

      final responseData = data['response'];

      if (responseData is! List || responseData.isEmpty) {
        return null;
      }

      final first = responseData.first;

      if (first is! Map<String, dynamic>) {
        return null;
      }

      final players = first['players'];

      if (players is! List) {
        return null;
      }

      return players.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      print('SMARTBET PROFILE /players/squads ERROR: $e');

      return null;
    }
  }

  // ============================================================
  // INFORTUNI / SQUALIFICHE
  // ============================================================

  Future<List<Map<String, dynamic>>?> _getUnavailablePlayers({
    required int teamId,
    required int season,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/injuries').replace(
      queryParameters: {'team': teamId.toString(), 'season': season.toString()},
    );

    try {
      final response = await _client.get(uri);

      print(
        'SMARTBET PROFILE /injuries '
        '$teamId → ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        return null;
      }

      final responseData = data['response'];

      if (responseData is! List) {
        return null;
      }

      return responseData.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      print('SMARTBET PROFILE /injuries ERROR: $e');

      return null;
    }
  }

  // ============================================================
  // APPLICA STATISTICHE
  // ============================================================

  TeamProfile _applyStatistics(TeamProfile profile, Map<String, dynamic> data) {
    final fixtures = data['fixtures'];
    final goals = data['goals'];

    if (fixtures is! Map<String, dynamic> || goals is! Map<String, dynamic>) {
      return profile;
    }

    final played = _extractInt(fixtures['played']);

    final wins = _extractInt(fixtures['wins']);

    final draws = _extractInt(fixtures['draws']);

    final goalsFor = _extractGoals(goals['for']);

    final goalsAgainst = _extractGoals(goals['against']);

    // ==========================================================
    // FORMA
    // ==========================================================

    int form = 50;

    if (played > 0) {
      final points = (wins * 3) + draws;

      final maximum = played * 3;

      form = ((points / maximum) * 100).round().clamp(0, 100);
    }

    // ==========================================================
    // ATTACCO
    // ==========================================================

    int attack = 50;

    if (played > 0) {
      final goalsPerMatch = goalsFor / played;

      attack = ((goalsPerMatch / 3) * 100).round().clamp(0, 100);
    }

    // ==========================================================
    // DIFESA
    // ==========================================================

    int defense = 50;

    if (played > 0) {
      final concededPerMatch = goalsAgainst / played;

      defense = (100 - ((concededPerMatch / 3) * 100)).round().clamp(0, 100);
    }

    // ==========================================================
    // CASA
    // ==========================================================

    final home = _extractVenueData(fixtures['home']);

    final homeTotal = home['wins']! + home['draws']! + home['losses']!;

    int homeStrength = 50;

    if (homeTotal > 0) {
      final points = (home['wins']! * 3) + home['draws']!;

      homeStrength = ((points / (homeTotal * 3)) * 100).round().clamp(0, 100);
    }

    // ==========================================================
    // TRASFERTA
    // ==========================================================

    final away = _extractVenueData(fixtures['away']);

    final awayTotal = away['wins']! + away['draws']! + away['losses']!;

    int awayStrength = 50;

    if (awayTotal > 0) {
      final points = (away['wins']! * 3) + away['draws']!;

      awayStrength = ((points / (awayTotal * 3)) * 100).round().clamp(0, 100);
    }

    // ==========================================================
    // FORZA GENERALE
    // ==========================================================

    final strength =
        ((form * 0.35) +
                (attack * 0.25) +
                (defense * 0.25) +
                (((homeStrength + awayStrength) / 2) * 0.15))
            .round()
            .clamp(0, 100);

    return TeamProfile(
      teamId: profile.teamId,
      teamName: profile.teamName,
      country: profile.country,
      league: profile.league,
      strength: strength,
      squadStrength: profile.squadStrength,
      attackStrength: attack,
      defenseStrength: defense,
      form: form,
      homeStrength: homeStrength,
      awayStrength: awayStrength,
      historicalStrength: profile.historicalStrength,
      leagueStrength: profile.leagueStrength,
      injuredPlayers: profile.injuredPlayers,
      suspendedPlayers: profile.suspendedPlayers,
      unavailablePlayers: profile.unavailablePlayers,
      dataConfidence: (profile.dataConfidence + 35).clamp(0, 100),
    );
  }

  // ============================================================
  // APPLICA ROSA
  // ============================================================

  TeamProfile _applySquad(
    TeamProfile profile,
    List<Map<String, dynamic>> players,
  ) {
    if (players.isEmpty) {
      return profile;
    }

    final squadStrength = players.length >= 25
        ? 65
        : players.length >= 20
        ? 60
        : players.length >= 16
        ? 55
        : 50;

    return TeamProfile(
      teamId: profile.teamId,
      teamName: profile.teamName,
      country: profile.country,
      league: profile.league,
      strength: profile.strength,
      squadStrength: squadStrength,
      attackStrength: profile.attackStrength,
      defenseStrength: profile.defenseStrength,
      form: profile.form,
      homeStrength: profile.homeStrength,
      awayStrength: profile.awayStrength,
      historicalStrength: profile.historicalStrength,
      leagueStrength: profile.leagueStrength,
      injuredPlayers: profile.injuredPlayers,
      suspendedPlayers: profile.suspendedPlayers,
      unavailablePlayers: profile.unavailablePlayers,
      dataConfidence: (profile.dataConfidence + 10).clamp(0, 100),
    );
  }

  // ============================================================
  // APPLICA ASSENZE
  // ============================================================

  TeamProfile _applyUnavailablePlayers(
    TeamProfile profile,
    List<Map<String, dynamic>> players,
  ) {
    int injured = 0;
    int suspended = 0;

    for (final item in players) {
      final player = item['player'];

      final absence = item['type']?.toString().toLowerCase();

      if (absence == 'missing') {
        injured++;
      } else if (absence == 'suspension' || absence == 'suspended') {
        suspended++;
      } else if (player != null) {
        injured++;
      }
    }

    final unavailable = injured + suspended;

    return TeamProfile(
      teamId: profile.teamId,
      teamName: profile.teamName,
      country: profile.country,
      league: profile.league,
      strength: profile.strength,
      squadStrength: profile.squadStrength,
      attackStrength: profile.attackStrength,
      defenseStrength: profile.defenseStrength,
      form: profile.form,
      homeStrength: profile.homeStrength,
      awayStrength: profile.awayStrength,
      historicalStrength: profile.historicalStrength,
      leagueStrength: profile.leagueStrength,
      injuredPlayers: injured,
      suspendedPlayers: suspended,
      unavailablePlayers: unavailable,
      dataConfidence: (profile.dataConfidence + 10).clamp(0, 100),
    );
  }

  // ============================================================
  // COUNTRY
  // ============================================================

  String _extractCountry(Map<String, dynamic> team, String fallback) {
    final country = team['country'];

    if (country is String && country.trim().isNotEmpty) {
      return country;
    }

    return fallback;
  }

  // ============================================================
  // HEADERS
  // ============================================================

  // ============================================================
  // CONVERSIONE INT
  // ============================================================

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

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  // ============================================================
  // GOL
  // ============================================================

  int _extractGoals(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _extractInt(value['total']);
    }

    return _extractInt(value);
  }

  // ============================================================
  // CASA / TRASFERTA
  // ============================================================

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
