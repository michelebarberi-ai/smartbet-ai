import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class TeamFormData {
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

  final List<String> recentResults;

  const TeamFormData({
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
    required this.recentResults,
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

  double get formPoints {
    if (matchesPlayed == 0) {
      return 0;
    }

    return ((wins * 3) + draws) / (matchesPlayed * 3);
  }

  int get formScore {
    return (formPoints * 100).round().clamp(0, 100);
  }

  int get attackScore {
    if (matchesPlayed == 0) {
      return 0;
    }

    final score = (goalsPerMatch / 3) * 100;

    return score.round().clamp(0, 100);
  }

  int get defenseScore {
    if (matchesPlayed == 0) {
      return 0;
    }

    final score = 100 - ((concededPerMatch / 3) * 100);

    return score.round().clamp(0, 100);
  }

  int get homePerformance {
    final total = homeWins + homeDraws + homeLosses;

    if (total == 0) {
      return 50;
    }

    final points = (homeWins * 3) + homeDraws;

    return ((points / (total * 3)) * 100).round().clamp(0, 100);
  }

  int get awayPerformance {
    final total = awayWins + awayDraws + awayLosses;

    if (total == 0) {
      return 50;
    }

    final points = (awayWins * 3) + awayDraws;

    return ((points / (total * 3)) * 100).round().clamp(0, 100);
  }
}

class TeamFormService {
  final http.Client _client;

  TeamFormService({http.Client? client}) : _client = client ?? http.Client();

  // ============================================================
  // CACHE
  // ============================================================

  static final Map<String, TeamFormData> _cache = {};

  static final Map<String, DateTime> _cacheTime = {};

  static const Duration _cacheDuration = Duration(minutes: 30);

  // ============================================================
  // ULTIME PARTITE
  // ============================================================

  Future<TeamFormData?> getTeamForm({
    required int teamId,
    int last = 10,
  }) async {
    if (teamId <= 0) {
      return null;
    }

    final cacheKey = '$teamId-$last';

    final cached = _cache[cacheKey];

    final cachedTime = _cacheTime[cacheKey];

    if (cached != null &&
        cachedTime != null &&
        DateTime.now().difference(cachedTime) < _cacheDuration) {
      return cached;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/fixtures').replace(
      queryParameters: {'team': teamId.toString(), 'last': last.toString()},
    );

    try {
      final response = await _client.get(
        uri,
        headers: {'x-apisports-key': ApiConfig.apiKey},
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
        return null;
      }

      final responseData = data['response'];

      if (responseData is! List<dynamic>) {
        return null;
      }

      final result = _calculateForm(teamId: teamId, fixtures: responseData);

      if (result == null) {
        return null;
      }

      _cache[cacheKey] = result;
      _cacheTime[cacheKey] = DateTime.now();

      return result;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // CALCOLO
  // ============================================================

  TeamFormData? _calculateForm({
    required int teamId,
    required List<dynamic> fixtures,
  }) {
    int wins = 0;
    int draws = 0;
    int losses = 0;

    int goalsFor = 0;
    int goalsAgainst = 0;

    int homeWins = 0;
    int homeDraws = 0;
    int homeLosses = 0;

    int awayWins = 0;
    int awayDraws = 0;
    int awayLosses = 0;

    String teamName = '';

    final recentResults = <String>[];

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

      if (home is! Map<String, dynamic>) {
        continue;
      }

      if (away is! Map<String, dynamic>) {
        continue;
      }

      final homeId = _toInt(home['id']);

      final awayId = _toInt(away['id']);

      if (homeId != teamId && awayId != teamId) {
        continue;
      }

      final homeName = home['name']?.toString() ?? '';

      final awayName = away['name']?.toString() ?? '';

      if (teamName.isEmpty) {
        teamName = homeId == teamId ? homeName : awayName;
      }

      final homeGoals = _toInt(goals['home']);

      final awayGoals = _toInt(goals['away']);

      // --------------------------------------------------------
      // EVITIAMO PARTITE NON CONCLUSE
      // --------------------------------------------------------

      if (goals['home'] == null || goals['away'] == null) {
        continue;
      }

      final isHome = homeId == teamId;

      final scored = isHome ? homeGoals : awayGoals;

      final conceded = isHome ? awayGoals : homeGoals;

      goalsFor += scored;
      goalsAgainst += conceded;

      // --------------------------------------------------------
      // RISULTATO
      // --------------------------------------------------------

      String result;

      if (scored > conceded) {
        wins++;
        result = 'W';

        if (isHome) {
          homeWins++;
        } else {
          awayWins++;
        }
      } else if (scored == conceded) {
        draws++;
        result = 'D';

        if (isHome) {
          homeDraws++;
        } else {
          awayDraws++;
        }
      } else {
        losses++;
        result = 'L';

        if (isHome) {
          homeLosses++;
        } else {
          awayLosses++;
        }
      }

      recentResults.add(result);
    }

    final matchesPlayed = wins + draws + losses;

    if (matchesPlayed == 0) {
      return null;
    }

    return TeamFormData(
      teamId: teamId,
      teamName: teamName,
      matchesPlayed: matchesPlayed,
      wins: wins,
      draws: draws,
      losses: losses,
      goalsFor: goalsFor,
      goalsAgainst: goalsAgainst,
      homeWins: homeWins,
      homeDraws: homeDraws,
      homeLosses: homeLosses,
      awayWins: awayWins,
      awayDraws: awayDraws,
      awayLosses: awayLosses,
      recentResults: recentResults,
    );
  }

  // ============================================================
  // CONVERSIONE INT
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
  // PULIZIA CACHE
  // ============================================================

  static void clearCache() {
    _cache.clear();
    _cacheTime.clear();
  }

  void dispose() {
    _client.close();
  }
}
