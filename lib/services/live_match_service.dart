import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class LiveMatchSummary {
  final int fixtureId;

  final int homeTeamId;
  final int awayTeamId;

  final String homeTeam;
  final String awayTeam;

  final String leagueName;
  final String country;

  final int homeGoals;
  final int awayGoals;

  final int elapsed;
  final String statusShort;
  final String statusLong;

  const LiveMatchSummary({
    required this.fixtureId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeTeam,
    required this.awayTeam,
    required this.leagueName,
    required this.country,
    required this.homeGoals,
    required this.awayGoals,
    required this.elapsed,
    required this.statusShort,
    required this.statusLong,
  });

  factory LiveMatchSummary.fromJson(Map<String, dynamic> json) {
    final fixture =
        (json['fixture'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    final status =
        (fixture['status'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    final teams =
        (json['teams'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final home =
        (teams['home'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final away =
        (teams['away'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final goals =
        (json['goals'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final league =
        (json['league'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    return LiveMatchSummary(
      fixtureId: _toInt(fixture['id']),
      homeTeamId: _toInt(home['id']),
      awayTeamId: _toInt(away['id']),
      homeTeam: home['name']?.toString() ?? 'Casa',
      awayTeam: away['name']?.toString() ?? 'Ospite',
      leagueName: league['name']?.toString() ?? '',
      country: league['country']?.toString() ?? '',
      homeGoals: _toInt(goals['home']),
      awayGoals: _toInt(goals['away']),
      elapsed: _toInt(status['elapsed']),
      statusShort: status['short']?.toString() ?? '',
      statusLong: status['long']?.toString() ?? '',
    );
  }
}

class LiveTeamStats {
  final int teamId;
  final String teamName;

  final double shotsOnGoal;
  final double totalShots;
  final double shotsInsideBox;

  final double possession;

  final double corners;
  final double fouls;

  final double yellowCards;
  final double redCards;

  final double goalkeeperSaves;

  final double? expectedGoals;

  const LiveTeamStats({
    required this.teamId,
    required this.teamName,
    required this.shotsOnGoal,
    required this.totalShots,
    required this.shotsInsideBox,
    required this.possession,
    required this.corners,
    required this.fouls,
    required this.yellowCards,
    required this.redCards,
    required this.goalkeeperSaves,
    required this.expectedGoals,
  });

  factory LiveTeamStats.empty({required int teamId, required String teamName}) {
    return LiveTeamStats(
      teamId: teamId,
      teamName: teamName,
      shotsOnGoal: 0,
      totalShots: 0,
      shotsInsideBox: 0,
      possession: 0,
      corners: 0,
      fouls: 0,
      yellowCards: 0,
      redCards: 0,
      goalkeeperSaves: 0,
      expectedGoals: null,
    );
  }

  factory LiveTeamStats.fromJson(Map<String, dynamic> json) {
    final team =
        (json['team'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final rawStats = json['statistics'];

    final values = <String, dynamic>{};

    if (rawStats is List) {
      for (final raw in rawStats) {
        if (raw is! Map) continue;

        final item = raw.cast<String, dynamic>();
        final type = item['type']?.toString();

        if (type != null) {
          values[type] = item['value'];
        }
      }
    }

    return LiveTeamStats(
      teamId: _toInt(team['id']),
      teamName: team['name']?.toString() ?? '',
      shotsOnGoal: _toDouble(values['Shots on Goal']),
      totalShots: _toDouble(values['Total Shots']),
      shotsInsideBox: _toDouble(values['Shots insidebox']),
      possession: _toDouble(values['Ball Possession']),
      corners: _toDouble(values['Corner Kicks']),
      fouls: _toDouble(values['Fouls']),
      yellowCards: _toDouble(values['Yellow Cards']),
      redCards: _toDouble(values['Red Cards']),
      goalkeeperSaves: _toDouble(values['Goalkeeper Saves']),
      expectedGoals: _toNullableDouble(
        values['expected_goals'] ??
            values['Expected Goals'] ??
            values['Expected goals'],
      ),
    );
  }
}

class LiveMatchEvent {
  final int elapsed;
  final int extra;

  final int teamId;
  final String teamName;

  final String type;
  final String detail;

  final String playerName;
  final String assistName;

  const LiveMatchEvent({
    required this.elapsed,
    required this.extra,
    required this.teamId,
    required this.teamName,
    required this.type,
    required this.detail,
    required this.playerName,
    required this.assistName,
  });

  factory LiveMatchEvent.fromJson(Map<String, dynamic> json) {
    final time =
        (json['time'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final team =
        (json['team'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final player =
        (json['player'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    final assist =
        (json['assist'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    return LiveMatchEvent(
      elapsed: _toInt(time['elapsed']),
      extra: _toInt(time['extra']),
      teamId: _toInt(team['id']),
      teamName: team['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      playerName: player['name']?.toString() ?? '',
      assistName: assist['name']?.toString() ?? '',
    );
  }
}

class LiveMatchSnapshot {
  final LiveMatchSummary match;

  final LiveTeamStats homeStats;
  final LiveTeamStats awayStats;

  final List<LiveMatchEvent> events;

  const LiveMatchSnapshot({
    required this.match,
    required this.homeStats,
    required this.awayStats,
    required this.events,
  });
}

class LiveMatchService {
  Future<List<LiveMatchSummary>> getLiveMatches() async {
    final response = await _get('fixtures', const {
      'live': 'all',
      'timezone': 'Europe/Rome',
    });

    final matches = response
        .whereType<Map>()
        .map((item) => LiveMatchSummary.fromJson(item.cast<String, dynamic>()))
        .where((match) => match.fixtureId > 0)
        .toList();

    matches.sort((a, b) {
      final leagueCompare = a.leagueName.compareTo(b.leagueName);

      if (leagueCompare != 0) {
        return leagueCompare;
      }

      return b.elapsed.compareTo(a.elapsed);
    });

    return matches;
  }

  Future<LiveMatchSnapshot> getSnapshot(LiveMatchSummary match) async {
    final results = await Future.wait([
      _get('fixtures/statistics', {'fixture': match.fixtureId.toString()}),
      _get('fixtures/events', {'fixture': match.fixtureId.toString()}),
    ]);

    final rawStatistics = results[0];
    final rawEvents = results[1];

    LiveTeamStats homeStats = LiveTeamStats.empty(
      teamId: match.homeTeamId,
      teamName: match.homeTeam,
    );

    LiveTeamStats awayStats = LiveTeamStats.empty(
      teamId: match.awayTeamId,
      teamName: match.awayTeam,
    );

    for (final raw in rawStatistics) {
      if (raw is! Map) continue;

      final stats = LiveTeamStats.fromJson(raw.cast<String, dynamic>());

      if (stats.teamId == match.homeTeamId) {
        homeStats = stats;
      } else if (stats.teamId == match.awayTeamId) {
        awayStats = stats;
      }
    }

    final events = rawEvents
        .whereType<Map>()
        .map((item) => LiveMatchEvent.fromJson(item.cast<String, dynamic>()))
        .toList();

    events.sort((a, b) {
      final minuteCompare = a.elapsed.compareTo(b.elapsed);

      if (minuteCompare != 0) {
        return minuteCompare;
      }

      return a.extra.compareTo(b.extra);
    });

    return LiveMatchSnapshot(
      match: match,
      homeStats: homeStats,
      awayStats: awayStats,
      events: events,
    );
  }

  Future<List<dynamic>> _get(String path, Map<String, String> query) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/$path',
    ).replace(queryParameters: query);

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception(
        'Live API error ${response.statusCode}: '
        '${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Risposta Live API-Football non valida.');
    }

    final errors = decoded['errors'];

    if (errors is Map && errors.isNotEmpty) {
      throw Exception('Errore API-Football Live: $errors');
    }

    return (decoded['response'] as List<dynamic>?) ?? <dynamic>[];
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic value) {
  return _toNullableDouble(value) ?? 0;
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;

  if (value is num) {
    return value.toDouble();
  }

  final cleaned = value.toString().replaceAll('%', '').trim();

  if (cleaned.isEmpty) return null;

  return double.tryParse(cleaned);
}
