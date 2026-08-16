import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/match_model.dart';
import 'api_rate_limiter.dart';

class MatchContext {
  final List<String> recentMatchesHome;
  final List<String> recentMatchesAway;

  final List<String> headToHead;

  final List<String> injuriesHome;
  final List<String> injuriesAway;

  final List<String> probableLineupsHome;
  final List<String> probableLineupsAway;

  final int confidence;

  const MatchContext({
    required this.recentMatchesHome,
    required this.recentMatchesAway,
    required this.headToHead,
    required this.injuriesHome,
    required this.injuriesAway,
    required this.probableLineupsHome,
    required this.probableLineupsAway,
    required this.confidence,
  });

  Map<String, dynamic> toJson() {
    return {
      'recentMatches': {'home': recentMatchesHome, 'away': recentMatchesAway},
      'headToHead': headToHead,
      'injuries': {'home': injuriesHome, 'away': injuriesAway},
      'probableLineups': {
        'home': probableLineupsHome,
        'away': probableLineupsAway,
      },
      'confidence': confidence,
    };
  }
}

class _FixtureInjuryData {
  final List<String> home;
  final List<String> away;

  const _FixtureInjuryData({required this.home, required this.away});
}

class _FixtureLineupData {
  final List<String> home;
  final List<String> away;

  const _FixtureLineupData({required this.home, required this.away});
}

class ContextResearcher {
  final http.Client _client;

  ContextResearcher({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers {
    return {'x-apisports-key': ApiConfig.apiKey, 'Accept': 'application/json'};
  }

  // ============================================================
  // RICERCA COMPLETA
  // ============================================================

  Future<MatchContext> research(MatchModel match) async {
    print('');
    print('========================================');
    print('SMARTBET - CONTEXT RESEARCHER');
    print('========================================');
    print('Partita: ${match.homeTeam} - ${match.awayTeam}');
    print('Home ID: ${match.homeTeamId}');
    print('Away ID: ${match.awayTeamId}');
    print('Data: ${match.date}');

    // ==========================================================
    // FORMA CASA
    // ==========================================================

    final recentHome = await _getRecentMatches(
      teamId: match.homeTeamId,
      teamName: match.homeTeam,
      matchDate: match.date,
    );

    // ==========================================================
    // FORMA OSPITE
    // ==========================================================

    final recentAway = await _getRecentMatches(
      teamId: match.awayTeamId,
      teamName: match.awayTeam,
      matchDate: match.date,
    );

    // ==========================================================
    // H2H
    // ==========================================================

    final h2h = await _getHeadToHead(
      homeTeamId: match.homeTeamId,
      awayTeamId: match.awayTeamId,
      matchDate: match.date,
    );

    // ==========================================================
    // ASSENZE
    // ==========================================================
    //
    // UNA SOLA chiamata per la fixture.
    // La risposta viene separata internamente tra casa e ospite.
    //
    // Non facciamo fallback stagionali.
    // ==========================================================

    final injuryData = await _getFixtureInjuries(
      fixtureId: match.fixtureId,
      homeTeamId: match.homeTeamId,
      awayTeamId: match.awayTeamId,
    );

    // ==========================================================
    // LINEUP
    // ==========================================================
    //
    // UNA SOLA chiamata per la fixture.
    // La risposta contiene entrambe le squadre.
    // ==========================================================

    final lineupData = await _getFixtureLineups(
      fixtureId: match.fixtureId,
      homeTeamId: match.homeTeamId,
      awayTeamId: match.awayTeamId,
      homeTeamName: match.homeTeam,
      awayTeamName: match.awayTeam,
    );

    // ==========================================================
    // CONFIDENCE CONTESTO
    // ==========================================================

    int availableSources = 0;

    if (recentHome.isNotEmpty) {
      availableSources++;
    }

    if (recentAway.isNotEmpty) {
      availableSources++;
    }

    if (h2h.isNotEmpty) {
      availableSources++;
    }

    if (injuryData.home.isNotEmpty || injuryData.away.isNotEmpty) {
      availableSources++;
    }

    if (lineupData.home.isNotEmpty || lineupData.away.isNotEmpty) {
      availableSources++;
    }

    final confidence = ((availableSources / 5) * 100).round().clamp(0, 100);

    // ==========================================================
    // LOG
    // ==========================================================

    print('');
    print('========================================');
    print('CONTEXT RESEARCH COMPLETATO');
    print('========================================');
    print('Forma casa: ${recentHome.length} partite');
    print('Forma ospite: ${recentAway.length} partite');
    print('H2H: ${h2h.length}');
    print('Assenze casa: ${injuryData.home.length}');
    print('Assenze ospite: ${injuryData.away.length}');
    print('Formazione casa: ${lineupData.home.length}');
    print('Formazione ospite: ${lineupData.away.length}');
    print('Context confidence: $confidence%');
    print('========================================');

    return MatchContext(
      recentMatchesHome: recentHome,
      recentMatchesAway: recentAway,
      headToHead: h2h,
      injuriesHome: injuryData.home,
      injuriesAway: injuryData.away,
      probableLineupsHome: lineupData.home,
      probableLineupsAway: lineupData.away,
      confidence: confidence,
    );
  }

  // ============================================================
  // ULTIME PARTITE
  // ============================================================

  Future<List<String>> _getRecentMatches({
    required int teamId,
    required String teamName,
    required String matchDate,
  }) async {
    print('');
    print('RICERCA FORMA');
    print('Squadra: $teamName');

    final targetDate = DateTime.tryParse(matchDate);

    if (targetDate == null) {
      print('Data partita non valida');
      return [];
    }

    final seasons = _candidateSeasons(targetDate);

    final collected = <Map<String, dynamic>>[];

    for (final season in seasons) {
      print('Provo stagione: $season');

      final uri = Uri.parse('${ApiConfig.baseUrl}/fixtures').replace(
        queryParameters: {
          'team': teamId.toString(),
          'season': season.toString(),
        },
      );

      try {
        // ======================================================
        // RATE LIMITER
        // ======================================================

        await ApiRateLimiter.wait();

        final response = await _client.get(uri, headers: _headers);

        print(
          'FORMA STATUS [$season]: '
          '${response.statusCode}',
        );

        if (response.statusCode != 200) {
          continue;
        }

        final decoded = jsonDecode(response.body);

        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final errors = decoded['errors'];

        if (errors is Map && errors.isNotEmpty) {
          print(
            'FORMA API ERROR [$season]: '
            '$errors',
          );

          continue;
        }

        final fixtures = decoded['response'];

        if (fixtures is! List) {
          continue;
        }

        for (final item in fixtures) {
          if (item is! Map<String, dynamic>) {
            continue;
          }

          final fixture = item['fixture'];
          final teams = item['teams'];
          final goals = item['goals'];

          if (fixture is! Map<String, dynamic> ||
              teams is! Map<String, dynamic> ||
              goals is! Map<String, dynamic>) {
            continue;
          }

          final fixtureDate = DateTime.tryParse(
            fixture['date']?.toString() ?? '',
          );

          if (fixtureDate == null) {
            continue;
          }

          // ----------------------------------------------------
          // SOLO PARTITE PRECEDENTI ALLA GARA
          // ----------------------------------------------------

          if (!fixtureDate.isBefore(targetDate)) {
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

          final homeGoals = _nullableInt(goals['home']);

          final awayGoals = _nullableInt(goals['away']);

          if (homeGoals == null || awayGoals == null) {
            continue;
          }

          final homeName = home['name']?.toString() ?? '';

          final awayName = away['name']?.toString() ?? '';

          collected.add({
            'date': fixtureDate,
            'fixtureId': _toInt(fixture['id']),
            'text':
                '$homeName '
                '$homeGoals-$awayGoals '
                '$awayName',
          });
        }
      } catch (e) {
        print('FORMA EXCEPTION [$season]: $e');
      }
    }

    // ==========================================================
    // RIMUOVIAMO DUPLICATI
    // ==========================================================

    final unique = <int, Map<String, dynamic>>{};

    for (final item in collected) {
      final id = _toInt(item['fixtureId']);

      if (id > 0) {
        unique[id] = item;
      }
    }

    final ordered = unique.values.toList();

    ordered.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
    );

    final result = ordered
        .take(10)
        .map<String>((item) => item['text'].toString())
        .toList();

    print(
      'PARTITE FORMA TROVATE: '
      '${result.length}',
    );

    return result;
  }

  // ============================================================
  // HEAD TO HEAD
  // ============================================================

  Future<List<String>> _getHeadToHead({
    required int homeTeamId,
    required int awayTeamId,
    required String matchDate,
  }) async {
    print('');
    print('RICERCA HEAD TO HEAD');

    final targetDate = DateTime.tryParse(matchDate);

    if (targetDate == null) {
      print('Data partita non valida per H2H');

      return [];
    }

    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/fixtures/headtohead',
      ).replace(queryParameters: {'h2h': '$homeTeamId-$awayTeamId'});

      // ========================================================
      // RATE LIMITER
      // ========================================================

      await ApiRateLimiter.wait();

      final response = await _client.get(uri, headers: _headers);

      print(
        'H2H STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('H2H API ERROR: $errors');

        return [];
      }

      final fixtures = decoded['response'];

      if (fixtures is! List) {
        return [];
      }

      final matches = <Map<String, dynamic>>[];

      for (final item in fixtures) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final fixture = item['fixture'];
        final teams = item['teams'];
        final goals = item['goals'];

        if (fixture is! Map<String, dynamic> ||
            teams is! Map<String, dynamic> ||
            goals is! Map<String, dynamic>) {
          continue;
        }

        final fixtureDate = DateTime.tryParse(
          fixture['date']?.toString() ?? '',
        );

        if (fixtureDate == null) {
          continue;
        }

        if (!fixtureDate.isBefore(targetDate)) {
          continue;
        }

        final home = teams['home'];
        final away = teams['away'];

        if (home is! Map<String, dynamic> || away is! Map<String, dynamic>) {
          continue;
        }

        final homeGoals = _nullableInt(goals['home']);

        final awayGoals = _nullableInt(goals['away']);

        if (homeGoals == null || awayGoals == null) {
          continue;
        }

        final homeName = home['name']?.toString() ?? '';

        final awayName = away['name']?.toString() ?? '';

        matches.add({
          'date': fixtureDate,
          'text':
              '${fixtureDate.toIso8601String()}: '
              '$homeName '
              '$homeGoals-$awayGoals '
              '$awayName',
        });
      }

      matches.sort(
        (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
      );

      final result = matches
          .take(10)
          .map<String>((item) => item['text'].toString())
          .toList();

      print(
        'H2H TROVATI: '
        '${result.length}',
      );

      return result;
    } catch (e) {
      print('H2H EXCEPTION: $e');

      return [];
    }
  }

  // ============================================================
  // ASSENZE - UNA SOLA CHIAMATA
  // ============================================================

  Future<_FixtureInjuryData> _getFixtureInjuries({
    required int fixtureId,
    required int homeTeamId,
    required int awayTeamId,
  }) async {
    print('');
    print('RICERCA ASSENZE FIXTURE');

    if (fixtureId <= 0) {
      print('Fixture ID non disponibile');

      return const _FixtureInjuryData(home: [], away: []);
    }

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/injuries',
    ).replace(queryParameters: {'fixture': fixtureId.toString()});

    try {
      // ========================================================
      // RATE LIMITER
      // ========================================================

      await ApiRateLimiter.wait();

      final response = await _client.get(uri, headers: _headers);

      print(
        'ASSENZE FIXTURE STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return const _FixtureInjuryData(home: [], away: []);
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return const _FixtureInjuryData(home: [], away: []);
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print(
          'ASSENZE FIXTURE API ERROR: '
          '$errors',
        );

        return const _FixtureInjuryData(home: [], away: []);
      }

      final data = decoded['response'];

      if (data is! List || data.isEmpty) {
        print('ASSENZE FIXTURE TROVATE: 0');

        return const _FixtureInjuryData(home: [], away: []);
      }

      final homeResult = <String>[];
      final awayResult = <String>[];

      for (final item in data) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final team = item['team'];
        final player = item['player'];

        if (team is! Map<String, dynamic> || player is! Map<String, dynamic>) {
          continue;
        }

        final teamId = _toInt(team['id']);

        final playerName = player['name']?.toString().trim() ?? '';

        final reason = player['reason']?.toString().trim() ?? '';

        if (playerName.isEmpty) {
          continue;
        }

        final text = reason.isEmpty ? playerName : '$playerName - $reason';

        if (teamId == homeTeamId) {
          if (!homeResult.contains(text)) {
            homeResult.add(text);
          }
        } else if (teamId == awayTeamId) {
          if (!awayResult.contains(text)) {
            awayResult.add(text);
          }
        }
      }

      final limitedHome = homeResult.take(10).toList();

      final limitedAway = awayResult.take(10).toList();

      print(
        'ASSENZE CASA TROVATE: '
        '${limitedHome.length}',
      );

      print(
        'ASSENZE OSPITE TROVATE: '
        '${limitedAway.length}',
      );

      return _FixtureInjuryData(home: limitedHome, away: limitedAway);
    } catch (e) {
      print('ASSENZE FIXTURE EXCEPTION: $e');

      return const _FixtureInjuryData(home: [], away: []);
    }
  }

  // ============================================================
  // LINEUP - UNA SOLA CHIAMATA
  // ============================================================

  Future<_FixtureLineupData> _getFixtureLineups({
    required int fixtureId,
    required int homeTeamId,
    required int awayTeamId,
    required String homeTeamName,
    required String awayTeamName,
  }) async {
    print('');
    print('RICERCA FORMAZIONI FIXTURE');

    if (fixtureId <= 0) {
      print('Fixture ID non disponibile');

      return const _FixtureLineupData(home: [], away: []);
    }

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/fixtures/lineups',
    ).replace(queryParameters: {'fixture': fixtureId.toString()});

    try {
      // ========================================================
      // RATE LIMITER
      // ========================================================

      await ApiRateLimiter.wait();

      final response = await _client.get(uri, headers: _headers);

      print(
        'LINEUP FIXTURE STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return const _FixtureLineupData(home: [], away: []);
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return const _FixtureLineupData(home: [], away: []);
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print(
          'LINEUP FIXTURE API ERROR: '
          '$errors',
        );

        return const _FixtureLineupData(home: [], away: []);
      }

      final data = decoded['response'];

      if (data is! List || data.isEmpty) {
        print('LINEUP FIXTURE TROVATE: 0');

        return const _FixtureLineupData(home: [], away: []);
      }

      final homeResult = <String>[];
      final awayResult = <String>[];

      for (final item in data) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final team = item['team'];

        if (team is! Map<String, dynamic>) {
          continue;
        }

        final teamId = _toInt(team['id']);

        if (teamId != homeTeamId && teamId != awayTeamId) {
          continue;
        }

        final teamNameFromApi =
            team['name']?.toString() ??
            (teamId == homeTeamId ? homeTeamName : awayTeamName);

        final target = teamId == homeTeamId ? homeResult : awayResult;

        final formation = item['formation']?.toString() ?? '';

        if (formation.isNotEmpty) {
          target.add(
            '$teamNameFromApi - '
            'modulo $formation',
          );
        }

        final startXI = item['startXI'];

        if (startXI is List) {
          for (final playerData in startXI) {
            if (playerData is! Map<String, dynamic>) {
              continue;
            }

            final player = playerData['player'];

            if (player is! Map<String, dynamic>) {
              continue;
            }

            final name = player['name']?.toString() ?? '';

            final number = player['number']?.toString() ?? '';

            final pos = player['pos']?.toString() ?? '';

            if (name.isEmpty) {
              continue;
            }

            target.add(
              '$name'
              '${number.isEmpty ? '' : ' #$number'}'
              '${pos.isEmpty ? '' : ' [$pos]'}',
            );
          }
        }
      }

      print(
        'FORMAZIONE CASA TROVATA: '
        '${homeResult.length}',
      );

      print(
        'FORMAZIONE OSPITE TROVATA: '
        '${awayResult.length}',
      );

      return _FixtureLineupData(home: homeResult, away: awayResult);
    } catch (e) {
      print('LINEUP FIXTURE EXCEPTION: $e');

      return const _FixtureLineupData(home: [], away: []);
    }
  }

  // ============================================================
  // STAGIONI CANDIDATE
  // ============================================================

  List<int> _candidateSeasons(DateTime matchDate) {
    final year = matchDate.year;

    return [year, year - 1];
  }

  // ============================================================
  // CONVERSIONI
  // ============================================================

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _nullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(value.toString());
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _client.close();
  }
}
