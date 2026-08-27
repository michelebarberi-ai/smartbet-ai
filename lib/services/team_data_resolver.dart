import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_rate_limiter.dart';
import 'historical_team_service.dart';

class ResolvedTeamData {
  final int teamId;
  final String teamName;

  final int? sourceTeamId;
  final String sourceTeamName;

  final String dataSource;

  // ============================================================
  // CATEGORIA ATTUALE
  // ============================================================

  final int currentLeagueId;
  final String currentLeagueName;
  final int currentLeagueSeason;

  // ============================================================
  // FONTE STATISTICA
  // ============================================================

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

    required this.currentLeagueId,
    required this.currentLeagueName,
    required this.currentLeagueSeason,

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
    required DateTime referenceDate,
  }) async {
    final referenceYear = referenceDate.year;

    final cacheKey = '$teamId|${teamName.toLowerCase()}|$referenceYear';

    if (_cache.containsKey(cacheKey)) {
      print('');
      print('SMARTBET CACHE HIT');
      print('Squadra: $teamName');
      print('Anno riferimento: $referenceYear');

      return _cache[cacheKey];
    }

    print('');
    print('========================================');
    print('SMARTBET - TEAM DATA RESOLVER');
    print('========================================');
    print('Squadra: $teamName');
    print('Team ID: $teamId');
    print('Anno riferimento: $referenceYear');

    final resolved = await _resolveRecentSeasons(
      teamId: teamId,
      teamName: teamName,
      referenceYear: referenceYear,
    );

    _cache[cacheKey] = resolved;

    return resolved;
  }

  // ============================================================
  // STAGIONE CORRENTE + PRECEDENTE
  // ============================================================

  Future<ResolvedTeamData?> _resolveRecentSeasons({
    required int teamId,
    required String teamName,
    required int referenceYear,
  }) async {
    final seasons = [referenceYear, referenceYear - 1];

    print('');
    print('========================================');
    print('SMARTBET - RICERCA DATI PERTINENTI');
    print('========================================');

    // ==========================================================
    // CATEGORIA ATTUALE
    // ==========================================================
    //
    // Cerchiamo prima la competizione di campionato della
    // stagione della partita.
    //
    // Questa informazione resta separata dalle statistiche.
    // ==========================================================

    int currentLeagueId = 0;
    String currentLeagueName = '';

    final currentLeagues = await _getTeamLeagues(
      teamId: teamId,
      season: referenceYear,
    );

    if (currentLeagues.isNotEmpty) {
      final currentCandidates = _sortLeagueCandidates(currentLeagues);

      for (final candidate in currentCandidates) {
        final leagueId = _toInt(candidate['leagueId']);

        final leagueName = candidate['leagueName']?.toString() ?? '';

        final leagueType = candidate['leagueType']?.toString() ?? '';

        if (leagueId <= 0) {
          continue;
        }

        if (!_isMainLeague(leagueName: leagueName, leagueType: leagueType)) {
          continue;
        }

        currentLeagueId = leagueId;
        currentLeagueName = leagueName;

        break;
      }
    }

    print('');
    print('CATEGORIA ATTUALE');
    print('Squadra: $teamName');

    if (currentLeagueId > 0) {
      print('Stagione: $referenceYear');
      print('League ID: $currentLeagueId');
      print('Campionato: $currentLeagueName');
    } else {
      print('Campionato attuale non identificato');
    }

    // ==========================================================
    // RICERCA STATISTICHE
    // ==========================================================

    for (final season in seasons) {
      print('');
      print('----------------------------------------');
      print('PROVA STAGIONE STATISTICA: $season');
      print('Squadra: $teamName');
      print('----------------------------------------');

      final leagues = season == referenceYear
          ? currentLeagues
          : await _getTeamLeagues(teamId: teamId, season: season);

      if (leagues.isEmpty) {
        print(
          'Nessuna competizione disponibile '
          'per $teamName nella stagione $season',
        );

        continue;
      }

      print('COMPETIZIONI TROVATE: ${leagues.length}');

      final orderedLeagues = _sortLeagueCandidates(leagues);

      // ========================================================
      // SOLO CAMPIONATI
      // ========================================================

      for (final candidate in orderedLeagues) {
        final leagueId = _toInt(candidate['leagueId']);

        final leagueName = candidate['leagueName']?.toString() ?? '';

        final leagueType = candidate['leagueType']?.toString() ?? '';

        if (leagueId <= 0) {
          continue;
        }

        if (!_isMainLeague(leagueName: leagueName, leagueType: leagueType)) {
          print('');
          print('COMPETIZIONE IGNORATA PER STATISTICHE');
          print('League: $leagueName');
          print('Tipo: $leagueType');

          continue;
        }

        print('');
        print('PROVA CAMPIONATO');
        print('League ID: $leagueId');
        print('League: $leagueName');
        print('Tipo: $leagueType');

        final historical = await _historicalService.getHistoricalData(
          teamId: teamId,
          teamName: teamName,
          season: season,
          leagueId: leagueId,
          leagueName: leagueName,
        );

        if (historical == null) {
          print(
            'Nessuna partita di campionato '
            'conclusa disponibile.',
          );

          continue;
        }

        // ------------------------------------------------------
        // MINIMO 3 PARTITE
        // ------------------------------------------------------

        if (historical.matchesPlayed < 3) {
          print(
            'Solo ${historical.matchesPlayed} '
            'partite di campionato concluse.',
          );

          print(
            'Campione troppo piccolo: '
            'provo la stagione precedente.',
          );

          continue;
        }

        final confidence = _confidenceForSeason(
          season: season,
          referenceYear: referenceYear,
          matchesPlayed: historical.matchesPlayed,
        );

        final result = ResolvedTeamData(
          teamId: teamId,
          teamName: teamName,

          sourceTeamId: historical.originalTeamId,

          sourceTeamName: historical.originalTeamName,

          dataSource: season == referenceYear
              ? 'Current season league data'
              : 'Previous season league data',

          // ====================================================
          // CATEGORIA ATTUALE
          // ====================================================
          currentLeagueId: currentLeagueId,

          currentLeagueName: currentLeagueName,

          currentLeagueSeason: referenceYear,

          // ====================================================
          // FONTE STATISTICA
          // ====================================================
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

        print('');
        print('========================================');
        print('DATI SMARTBET TROVATI');
        print('========================================');
        print('Squadra: $teamName');

        print('');
        print('CATEGORIA ATTUALE');
        print(
          '${result.currentLeagueSeason} - '
          '${result.currentLeagueName}',
        );

        print('');
        print('FONTE STATISTICA');
        print('Stagione: ${result.season}');
        print('Campionato: ${result.leagueName}');
        print('Partite: ${result.matchesPlayed}');

        print(
          'Record: '
          '${result.wins}V / '
          '${result.draws}X / '
          '${result.losses}S',
        );

        print(
          'Gol: '
          '${result.goalsFor} fatti / '
          '${result.goalsAgainst} subiti',
        );

        print(
          'Confidence: '
          '${(result.confidence * 100).round()}%',
        );

        print('Fonte: ${result.dataSource}');

        print('========================================');

        return result;
      }

      print('');
      print(
        'Nessun campionato utilizzabile '
        'nella stagione $season.',
      );
    }

    // ==========================================================
    // NESSUN DATO SUFFICIENTE
    // ==========================================================

    print('');
    print('========================================');
    print('DATI STATISTICI RECENTI NON DISPONIBILI');
    print('========================================');
    print('Squadra: $teamName');

    print(
      'Provate solamente le stagioni '
      '$referenceYear e ${referenceYear - 1}.',
    );

    print(
      'Amichevoli e coppe NON utilizzate '
      'come base statistica.',
    );

    print('Nessun fallback a stagioni più vecchie.');

    print('========================================');

    return null;
  }

  // ============================================================
  // CONTROLLO CAMPIONATO PRINCIPALE
  // ============================================================

  bool _isMainLeague({required String leagueName, required String leagueType}) {
    final type = leagueType.toLowerCase().trim();

    final name = leagueName.toLowerCase().trim();

    if (type != 'league') {
      return false;
    }

    if (_looksLikeFriendlyCompetition(name)) {
      return false;
    }

    if (_looksLikeYouthCompetition(name)) {
      return false;
    }

    return true;
  }

  // ============================================================
  // API: COMPETIZIONI DELLA SQUADRA
  // ============================================================

  Future<List<Map<String, dynamic>>> _getTeamLeagues({
    required int teamId,
    required int season,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/leagues').replace(
      queryParameters: {'team': teamId.toString(), 'season': season.toString()},
    );

    print('');
    print('URL: $uri');

    try {
      await ApiRateLimiter.wait();

      final response = await _client.get(uri);

      print('LEAGUES STATUS: ${response.statusCode}');

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('LEAGUES API ERROR:');
        print(errors);

        return [];
      }

      final responseData = decoded['response'];

      if (responseData is! List) {
        return [];
      }

      final result = <Map<String, dynamic>>[];

      for (final item in responseData) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final league = item['league'];

        if (league is! Map<String, dynamic>) {
          continue;
        }

        final leagueId = _toInt(league['id']);

        final leagueName = league['name']?.toString() ?? '';

        final leagueType = league['type']?.toString() ?? '';

        if (leagueId <= 0 || leagueName.isEmpty) {
          continue;
        }

        result.add({
          'leagueId': leagueId,
          'leagueName': leagueName,
          'leagueType': leagueType,
        });
      }

      return result;
    } catch (e) {
      print('LEAGUES EXCEPTION: $e');

      return [];
    }
  }

  // ============================================================
  // ORDINE COMPETIZIONI
  // ============================================================

  List<Map<String, dynamic>> _sortLeagueCandidates(
    List<Map<String, dynamic>> leagues,
  ) {
    final result = List<Map<String, dynamic>>.from(leagues);

    result.sort((a, b) {
      final scoreA = _leaguePriority(a);

      final scoreB = _leaguePriority(b);

      return scoreA.compareTo(scoreB);
    });

    return result;
  }

  int _leaguePriority(Map<String, dynamic> league) {
    final type = league['leagueType']?.toString().toLowerCase() ?? '';

    final name = league['leagueName']?.toString().toLowerCase() ?? '';

    if (type == 'league') {
      if (_looksLikeYouthCompetition(name)) {
        return 50;
      }

      return 0;
    }

    if (type == 'cup') {
      return 80;
    }

    return 100;
  }

  // ============================================================
  // CONTROLLO AMICHEVOLI
  // ============================================================

  bool _looksLikeFriendlyCompetition(String name) {
    return name.contains('friendly') ||
        name.contains('friendlies') ||
        name.contains('amichevol') ||
        name.contains('club friendly');
  }

  // ============================================================
  // CONTROLLO GIOVANILI
  // ============================================================

  bool _looksLikeYouthCompetition(String name) {
    return name.contains('u17') ||
        name.contains('u18') ||
        name.contains('u19') ||
        name.contains('u20') ||
        name.contains('u21') ||
        name.contains('u23') ||
        name.contains('youth') ||
        name.contains('primavera') ||
        name.contains('junior');
  }

  // ============================================================
  // CONFIDENCE
  // ============================================================

  double _confidenceForSeason({
    required int season,
    required int referenceYear,
    required int matchesPlayed,
  }) {
    // ----------------------------------------------------------
    // STAGIONE DELLA PARTITA
    // ----------------------------------------------------------

    if (season == referenceYear) {
      if (matchesPlayed >= 20) {
        return 0.90;
      }

      if (matchesPlayed >= 10) {
        return 0.82;
      }

      if (matchesPlayed >= 5) {
        return 0.72;
      }

      return 0.60;
    }

    // ----------------------------------------------------------
    // STAGIONE PRECEDENTE
    // ----------------------------------------------------------

    if (season == referenceYear - 1) {
      if (matchesPlayed >= 20) {
        return 0.65;
      }

      if (matchesPlayed >= 10) {
        return 0.58;
      }

      return 0.50;
    }

    return 0.30;
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

  // ============================================================
  // CACHE
  // ============================================================

  static void clearCache() {
    _cache.clear();

    HistoricalTeamService.clearCache();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _client.close();
  }
}
