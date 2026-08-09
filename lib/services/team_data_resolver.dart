import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'historical_team_service.dart';

class ResolvedTeamData {
  final int teamId;
  final String teamName;

  final int? sourceTeamId;
  final String sourceTeamName;

  final String dataSource;

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

  final double confidence;

  const ResolvedTeamData({
    required this.teamId,
    required this.teamName,
    required this.sourceTeamId,
    required this.sourceTeamName,
    required this.dataSource,
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
    required this.confidence,
  });

  double get winRate {
    if (matchesPlayed == 0) {
      return 0;
    }

    return wins / matchesPlayed;
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

  bool get isReliable {
    return confidence >= 0.70;
  }
}

class TeamDataResolver {
  final http.Client _client;

  late final HistoricalTeamService _historicalService;

  TeamDataResolver({http.Client? client}) : _client = client ?? http.Client() {
    _historicalService = HistoricalTeamService(client: _client);
  }

  // ============================================================
  // CACHE
  // ============================================================

  static final Map<String, ResolvedTeamData?> _cache = {};

  // ============================================================
  // RISOLUZIONE PRINCIPALE
  // ============================================================

  Future<ResolvedTeamData?> resolveTeam({
    required int teamId,
    required String teamName,
  }) async {
    final cacheKey = '$teamId|${teamName.toLowerCase()}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    print('');
    print('========================================');
    print('SMARTBET - TEAM DATA RESOLVER');
    print('========================================');
    print('Squadra: $teamName');
    print('Team ID: $teamId');

    // ----------------------------------------------------------
    // 1. PROVA DATI RECENTI
    // ----------------------------------------------------------

    final recent = await _tryRecentData(teamId: teamId, teamName: teamName);

    if (recent != null) {
      print('');
      print('DATI RECENTI TROVATI');
      print('Fonte: ${recent.dataSource}');
      print('Confidence: ${recent.confidence}');

      _cache[cacheKey] = recent;
      return recent;
    }

    // ----------------------------------------------------------
    // 2. FALLBACK STORICO
    // ----------------------------------------------------------

    print('');
    print('DATI RECENTI NON DISPONIBILI');
    print('Avvio fallback storico...');

    final historical = await _resolveHistoricalData(
      teamId: teamId,
      teamName: teamName,
    );

    _cache[cacheKey] = historical;

    return historical;
  }

  // ============================================================
  // DATI RECENTI
  // ============================================================

  Future<ResolvedTeamData?> _tryRecentData({
    required int teamId,
    required String teamName,
  }) async {
    print('');
    print('RICERCA DATI RECENTI');
    print('Team: $teamName');

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/fixtures',
    ).replace(queryParameters: {'team': teamId.toString(), 'last': '10'});

    print('URL: $uri');

    try {
      final response = await _client.get(uri, headers: _headers);

      print(
        'RECENT FIXTURES STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('RECENT API ERROR:');
        print(errors);
        return null;
      }

      final fixtures = decoded['response'];

      if (fixtures is! List || fixtures.isEmpty) {
        print('NESSUN FIXTURE RECENTE');
        return null;
      }

      final data = _calculateRecentData(
        fixtures,
        teamId: teamId,
        teamName: teamName,
      );

      if (data == null) {
        return null;
      }

      return data;
    } catch (e) {
      print('RECENT DATA EXCEPTION: $e');

      return null;
    }
  }

  // ============================================================
  // CALCOLO DATI RECENTI
  // ============================================================

  ResolvedTeamData? _calculateRecentData(
    List<dynamic> fixtures, {
    required int teamId,
    required String teamName,
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

    int? detectedLeagueId;
    String detectedLeagueName = '';

    int currentSeason = DateTime.now().year;

    for (final item in fixtures) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final fixture = item['fixture'];
      final teams = item['teams'];
      final goals = item['goals'];
      final league = item['league'];

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

      if (league is Map<String, dynamic>) {
        final id = _toInt(league['id']);

        if (id > 0 && detectedLeagueId == null) {
          detectedLeagueId = id;
        }

        if (detectedLeagueName.isEmpty) {
          detectedLeagueName = league['name']?.toString() ?? '';
        }
      }

      final homeGoals = _toInt(goals['home']);

      final awayGoals = _toInt(goals['away']);

      matchesPlayed++;

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
      } else {
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

    if (matchesPlayed < 3) {
      print(
        'Dati recenti insufficienti: '
        '$matchesPlayed partite',
      );

      return null;
    }

    return ResolvedTeamData(
      teamId: teamId,
      teamName: teamName,
      sourceTeamId: teamId,
      sourceTeamName: teamName,
      dataSource: 'API recent fixtures',
      season: currentSeason,
      leagueId: detectedLeagueId ?? 0,
      leagueName: detectedLeagueName,
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
      confidence: 0.85,
    );
  }

  // ============================================================
  // FALLBACK STORICO
  // ============================================================

  Future<ResolvedTeamData?> _resolveHistoricalData({
    required int teamId,
    required String teamName,
  }) async {
    int historicalTeamId = 0;
    String historicalTeamName = '';
    int season = 2024;
    int leagueId = 0;
    String leagueName = '';
    double confidence = 0.50;

    // ----------------------------------------------------------
    // UNION BRESCIA
    // ----------------------------------------------------------

    if (_normalize(teamName) == 'union brescia') {
      historicalTeamId = 884;
      historicalTeamName = 'Feralpisalo';
      leagueId = 138;
      leagueName = 'Serie C - Girone A';

      // La continuità storica è utile,
      // ma non deve avere lo stesso peso
      // dei dati della squadra attuale.
      confidence = 0.45;
    }
    // ----------------------------------------------------------
    // AREZZO
    // ----------------------------------------------------------
    else if (_normalize(teamName) == 'arezzo') {
      historicalTeamId = 876;
      historicalTeamName = 'Arezzo';
      leagueId = 942;
      leagueName = 'Serie C - Girone B';

      confidence = 0.65;
    }
    // ----------------------------------------------------------
    // SQUADRA NON MAPPATA
    // ----------------------------------------------------------
    else {
      print(
        'NESSUNO STORICO CONFIGURATO '
        'PER $teamName',
      );

      return null;
    }

    print('');
    print('FALLBACK STORICO');
    print('Squadra attuale: $teamName');
    print('Squadra storico: $historicalTeamName');
    print('Historical ID: $historicalTeamId');
    print('Season: $season');
    print('League ID: $leagueId');
    print('League: $leagueName');

    final historical = await _historicalService.getHistoricalData(
      teamId: historicalTeamId,
      teamName: historicalTeamName,
      season: season,
      leagueId: leagueId,
      leagueName: leagueName,
    );

    if (historical == null) {
      print('FALLBACK STORICO NON DISPONIBILE');

      return null;
    }

    return ResolvedTeamData(
      teamId: teamId,
      teamName: teamName,
      sourceTeamId: historical.originalTeamId,
      sourceTeamName: historical.originalTeamName,
      dataSource:
          'Historical fallback: '
          '${historical.originalTeamName}',
      season: historical.season,
      leagueId: historical.leagueId,
      leagueName: historical.leagueName,
      matchesPlayed: historical.matchesPlayed,
      wins: historical.wins,
      draws: historical.draws,
      losses: historical.losses,
      goalsFor: historical.goalsFor,
      goalsAgainst: historical.goalsAgainst,
      homeMatches: historical.homeMatches,
      homeWins: historical.homeWins,
      homeDraws: historical.homeDraws,
      homeLosses: historical.homeLosses,
      awayMatches: historical.awayMatches,
      awayWins: historical.awayWins,
      awayDraws: historical.awayDraws,
      awayLosses: historical.awayLosses,
      confidence: confidence,
    );
  }

  // ============================================================
  // NORMALIZZAZIONE
  // ============================================================

  String _normalize(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
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
  // HEADERS
  // ============================================================

  Map<String, String> get _headers {
    return {'x-apisports-key': ApiConfig.apiKey, 'Accept': 'application/json'};
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
    // HistoricalTeamService utilizza lo stesso client,
    // quindi chiudiamo il client una sola volta.
    _client.close();
  }
}
