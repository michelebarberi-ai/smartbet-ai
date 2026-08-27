import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_rate_limiter.dart';

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
  // STATI CONSIDERATI CONCLUSI
  // ============================================================

  static const Set<String> _finishedStatuses = {
    'FT',
    'AET',
    'PEN',
    'AWD',
    'WO',
  };

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
      print(
        'SMARTBET HISTORICAL: '
        'parametri non validi',
      );

      return null;
    }

    final cacheKey = '$teamId-$season-$leagueId';

    if (_cache.containsKey(cacheKey)) {
      print('');
      print('SMARTBET HISTORICAL CACHE HIT');
      print('Squadra: $teamName');
      print('Stagione: $season');

      return _cache[cacheKey];
    }

    print('');
    print('========================================');
    print('SMARTBET - HISTORICAL DATA');
    print('========================================');
    print('Squadra: $teamName');
    print('Team ID: $teamId');
    print('Stagione: $season');
    print('League ID: $leagueId');
    print('League: $leagueName');
    print('========================================');

    final uri = Uri.parse('${ApiConfig.baseUrl}/fixtures').replace(
      queryParameters: {
        'team': teamId.toString(),
        'season': season.toString(),
        'league': leagueId.toString(),
      },
    );

    try {
      // ========================================================
      // RATE LIMITER
      // ========================================================
      //
      // Tutte le richieste API-Football vengono distanziate
      // tramite il limiter condiviso.
      //
      // Questo evita picchi di richieste quando TeamDataResolver,
      // HistoricalTeamService e ContextResearcher lavorano
      // consecutivamente sulla stessa partita.
      // ========================================================

      await ApiRateLimiter.wait();

      final response = await _client.get(uri);

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
          'nessuna fixture trovata',
        );

        _cache[cacheKey] = null;
        return null;
      }

      print(
        'FIXTURE TOTALI API: '
        '${fixtures.length}',
      );

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

    int ignoredNotFinished = 0;
    int ignoredInvalidGoals = 0;
    int ignoredInvalidTeam = 0;

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

      // ========================================================
      // CONTROLLO STATO PARTITA
      // ========================================================

      final statusData = fixture['status'];

      String statusShort = '';

      if (statusData is Map<String, dynamic>) {
        statusShort =
            statusData['short']?.toString().toUpperCase().trim() ?? '';
      }

      // --------------------------------------------------------
      // IMPORTANTISSIMO:
      //
      // Una fixture futura/non terminata NON deve entrare
      // nelle statistiche.
      // --------------------------------------------------------

      if (!_finishedStatuses.contains(statusShort)) {
        ignoredNotFinished++;
        continue;
      }

      // ========================================================
      // CONTROLLO SQUADRE
      // ========================================================

      final home = teams['home'];
      final away = teams['away'];

      if (home is! Map<String, dynamic> || away is! Map<String, dynamic>) {
        ignoredInvalidTeam++;
        continue;
      }

      final homeId = _toInt(home['id']);
      final awayId = _toInt(away['id']);

      if (homeId != teamId && awayId != teamId) {
        ignoredInvalidTeam++;
        continue;
      }

      // ========================================================
      // CONTROLLO RISULTATO
      // ========================================================

      final homeGoals = _nullableInt(goals['home']);

      final awayGoals = _nullableInt(goals['away']);

      // --------------------------------------------------------
      // NULL NON DEVE DIVENTARE ZERO.
      // --------------------------------------------------------

      if (homeGoals == null || awayGoals == null) {
        ignoredInvalidGoals++;
        continue;
      }

      // ========================================================
      // PARTITA VALIDA
      // ========================================================

      matchesPlayed++;

      // ========================================================
      // CASA
      // ========================================================

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
      // ========================================================
      // TRASFERTA
      // ========================================================
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

    // ==========================================================
    // LOG FILTRAGGIO
    // ==========================================================

    print('');
    print('SMARTBET HISTORICAL FILTER');

    print('Fixture API: ${fixtures.length}');

    print(
      'Partite concluse utilizzate: '
      '$matchesPlayed',
    );

    print(
      'Ignorate non concluse: '
      '$ignoredNotFinished',
    );

    print(
      'Ignorate senza risultato: '
      '$ignoredInvalidGoals',
    );

    print(
      'Ignorate squadra non valida: '
      '$ignoredInvalidTeam',
    );

    // ==========================================================
    // NESSUNA PARTITA GIOCATA
    // ==========================================================

    if (matchesPlayed == 0) {
      print('');
      print('========================================');
      print('NESSUNA PARTITA CONCLUSA');
      print('========================================');
      print('Squadra: $teamName');
      print('Stagione: $season');

      print(
        'Le fixture esistono ma non risultano '
        'ancora partite concluse utilizzabili.',
      );

      print('========================================');

      return null;
    }

    // ==========================================================
    // RISULTATO
    // ==========================================================

    print('');
    print('========================================');
    print('SMARTBET HISTORICAL RISULTATO');
    print('========================================');
    print('Squadra: $teamName');
    print('Partite: $matchesPlayed');
    print('Vittorie: $wins');
    print('Pareggi: $draws');
    print('Sconfitte: $losses');
    print('Gol fatti: $goalsFor');
    print('Gol subiti: $goalsAgainst');

    print(
      'Casa: '
      '$homeWins V / '
      '$homeDraws X / '
      '$homeLosses S',
    );

    print(
      'Trasferta: '
      '$awayWins V / '
      '$awayDraws X / '
      '$awayLosses S',
    );

    print('========================================');

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
  // CONVERSIONE INT NULLABLE
  // ============================================================

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

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
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
