import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/match_model.dart';

class FootballDataContext {
  final bool available;
  final String source;
  final String competition;
  final String status;
  final String kickoff;
  final int confidence;
  final Map<String, dynamic> homeStanding;
  final Map<String, dynamic> awayStanding;
  final List<String> notes;

  const FootballDataContext({
    required this.available,
    required this.source,
    required this.competition,
    required this.status,
    required this.kickoff,
    required this.confidence,
    required this.homeStanding,
    required this.awayStanding,
    required this.notes,
  });

  factory FootballDataContext.unavailable({String reason = ''}) {
    return FootballDataContext(
      available: false,
      source: 'football-data.org',
      competition: '',
      status: '',
      kickoff: '',
      confidence: 0,
      homeStanding: const {},
      awayStanding: const {},
      notes: reason.isEmpty ? const [] : [reason],
    );
  }

  bool get hasStandings {
    return homeStanding.isNotEmpty && awayStanding.isNotEmpty;
  }

  List<String> get dossierLines {
    if (!available) {
      return const [];
    }

    final result = <String>[
      'Fonte secondaria verificata: football-data.org',
      if (competition.isNotEmpty) 'Competizione fonte secondaria: $competition',
      if (kickoff.isNotEmpty) 'Orario fonte secondaria: $kickoff',
      if (status.isNotEmpty) 'Stato fixture fonte secondaria: $status',
    ];

    if (homeStanding.isNotEmpty) {
      result.add(
        'Classifica casa fonte secondaria: '
        '${_standingText(homeStanding)}',
      );
    }

    if (awayStanding.isNotEmpty) {
      result.add(
        'Classifica ospite fonte secondaria: '
        '${_standingText(awayStanding)}',
      );
    }

    result.addAll(notes);

    return result;
  }

  static String _standingText(Map<String, dynamic> row) {
    final position = row['position'];
    final playedGames = row['playedGames'];
    final won = row['won'];
    final draw = row['draw'];
    final lost = row['lost'];
    final points = row['points'];
    final goalsFor = row['goalsFor'];
    final goalsAgainst = row['goalsAgainst'];
    final goalDifference = row['goalDifference'];
    final form = row['form']?.toString().trim() ?? '';

    final pieces = <String>[
      if (position != null) '#$position',
      if (playedGames != null) '${playedGames}G',
      if (won != null) '${won}V',
      if (draw != null) '${draw}N',
      if (lost != null) '${lost}P',
      if (points != null) '${points}pt',
      if (goalsFor != null && goalsAgainst != null)
        'GF/GS $goalsFor/$goalsAgainst',
      if (goalDifference != null) 'diff $goalDifference',
      if (form.isNotEmpty) 'forma $form',
    ];

    return pieces.join(' • ');
  }
}

class FootballDataService {
  final http.Client _client;

  FootballDataService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.football-data.org/v4';

  // football-data.org Free: 10 richieste/minuto.
  // Manteniamo un piccolo margine di sicurezza.
  static const Duration _minimumRequestGap = Duration(milliseconds: 6300);

  static DateTime? _lastRequestAt;
  static Future<void> _requestQueue = Future<void>.value();

  static final Map<String, Future<List<Map<String, dynamic>>>> _matchesCache =
      {};

  static final Map<int, Future<List<Map<String, dynamic>>>> _standingsCache =
      {};

  String get _apiKey {
    return dotenv.env['FOOTBALL_DATA_API_KEY']?.trim() ?? '';
  }

  Map<String, String> get _headers {
    return {'X-Auth-Token': _apiKey, 'Accept': 'application/json'};
  }

  Future<FootballDataContext> research(MatchModel match) async {
    if (_apiKey.isEmpty) {
      return FootballDataContext.unavailable(
        reason: 'FOOTBALL_DATA_API_KEY non configurata.',
      );
    }

    final targetDate = DateTime.tryParse(match.date);

    if (targetDate == null) {
      return FootballDataContext.unavailable(
        reason: 'Data partita non valida per la fonte secondaria.',
      );
    }

    try {
      final fixtures = await _getMatchesAround(targetDate);

      if (fixtures.isEmpty) {
        return FootballDataContext.unavailable(
          reason: 'Nessuna fixture disponibile dalla fonte secondaria.',
        );
      }

      final matched = _findBestMatch(
        fixtures: fixtures,
        match: match,
        targetDate: targetDate,
      );

      if (matched == null) {
        return FootballDataContext.unavailable(
          reason:
              'Partita non riconosciuta nella copertura gratuita football-data.org.',
        );
      }

      final competition = _asMap(matched['competition']);
      final homeTeam = _asMap(matched['homeTeam']);
      final awayTeam = _asMap(matched['awayTeam']);

      final competitionId = _toInt(competition['id']);
      final homeTeamId = _toInt(homeTeam['id']);
      final awayTeamId = _toInt(awayTeam['id']);

      Map<String, dynamic> homeStanding = {};
      Map<String, dynamic> awayStanding = {};

      // La classifica restituita da football-data.org rappresenta
      // lo stato corrente della competizione.
      //
      // Per una partita già disputata NON va utilizzata:
      // introdurrebbe informazioni successive alla data della gara
      // e quindi un potenziale data leakage nelle analisi storiche.
      final canUseCurrentStandings = targetDate.toUtc().isAfter(
        DateTime.now().toUtc(),
      );

      if (canUseCurrentStandings &&
          competitionId > 0 &&
          homeTeamId > 0 &&
          awayTeamId > 0) {
        final table = await _getCompetitionStandings(competitionId);

        homeStanding = _findStandingRow(table, homeTeamId);

        awayStanding = _findStandingRow(table, awayTeamId);
      }

      final matchConfidence = _matchConfidence(
        match.homeTeam,
        homeTeam['name']?.toString() ?? '',
        match.awayTeam,
        awayTeam['name']?.toString() ?? '',
      );

      final hasBothStandings =
          homeStanding.isNotEmpty && awayStanding.isNotEmpty;

      final confidence = hasBothStandings
          ? (82 + (matchConfidence * 18)).round().clamp(0, 100)
          : (62 + (matchConfidence * 18)).round().clamp(0, 100);

      final notes = <String>[
        'Controllo incrociato nomi squadre: '
            '${(matchConfidence * 100).round()}%',
        if (!hasBothStandings)
          'Classifica secondaria non disponibile '
              'per questa competizione o piano gratuito.',
      ];

      return FootballDataContext(
        available: true,
        source: 'football-data.org',
        competition: competition['name']?.toString() ?? '',
        status: matched['status']?.toString() ?? '',
        kickoff: matched['utcDate']?.toString() ?? '',
        confidence: confidence,
        homeStanding: homeStanding,
        awayStanding: awayStanding,
        notes: notes,
      );
    } catch (e) {
      print('FOOTBALL-DATA.ORG EXCEPTION: $e');

      return FootballDataContext.unavailable(
        reason: 'Fonte secondaria temporaneamente non disponibile.',
      );
    }
  }

  // ============================================================
  // FIXTURES
  // ============================================================

  Future<List<Map<String, dynamic>>> _getMatchesAround(DateTime targetDate) {
    final utc = targetDate.toUtc();
    final from = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
    ).subtract(const Duration(days: 1));

    final to = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
    ).add(const Duration(days: 1));

    final cacheKey = '${_dateOnly(from)}_${_dateOnly(to)}';

    return _matchesCache.putIfAbsent(
      cacheKey,
      () => _loadMatches(from: from, to: to),
    );
  }

  Future<List<Map<String, dynamic>>> _loadMatches({
    required DateTime from,
    required DateTime to,
  }) async {
    final uri = Uri.parse('$_baseUrl/matches').replace(
      queryParameters: {'dateFrom': _dateOnly(from), 'dateTo': _dateOnly(to)},
    );

    final response = await _queuedGet(uri);

    if (response == null) {
      return const [];
    }

    if (response.statusCode != 200) {
      print(
        'FOOTBALL-DATA MATCHES STATUS: '
        '${response.statusCode}',
      );

      return const [];
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final matches = decoded['matches'];

    if (matches is! List) {
      return const [];
    }

    return matches.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic>? _findBestMatch({
    required List<Map<String, dynamic>> fixtures,
    required MatchModel match,
    required DateTime targetDate,
  }) {
    Map<String, dynamic>? best;
    double bestScore = 0;

    for (final item in fixtures) {
      final home = _asMap(item['homeTeam']);
      final away = _asMap(item['awayTeam']);

      final homeName = home['name']?.toString() ?? '';
      final awayName = away['name']?.toString() ?? '';

      final homeSimilarity = _teamSimilarity(match.homeTeam, homeName);

      final awaySimilarity = _teamSimilarity(match.awayTeam, awayName);

      if (homeSimilarity < 0.48 || awaySimilarity < 0.48) {
        continue;
      }

      final apiDate = DateTime.tryParse(item['utcDate']?.toString() ?? '');

      var timeBonus = 0.0;

      if (apiDate != null) {
        final hours =
            apiDate.difference(targetDate.toUtc()).inMinutes.abs() / 60.0;

        if (hours <= 2) {
          timeBonus = 0.30;
        } else if (hours <= 8) {
          timeBonus = 0.20;
        } else if (hours <= 18) {
          timeBonus = 0.08;
        }
      }

      final score = homeSimilarity + awaySimilarity + timeBonus;

      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }

    if (bestScore < 1.25) {
      return null;
    }

    return best;
  }

  // ============================================================
  // CLASSIFICA
  // ============================================================

  Future<List<Map<String, dynamic>>> _getCompetitionStandings(
    int competitionId,
  ) {
    return _standingsCache.putIfAbsent(
      competitionId,
      () => _loadCompetitionStandings(competitionId),
    );
  }

  Future<List<Map<String, dynamic>>> _loadCompetitionStandings(
    int competitionId,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl/competitions/'
      '$competitionId/standings',
    );

    final response = await _queuedGet(uri);

    if (response == null) {
      return const [];
    }

    if (response.statusCode != 200) {
      print(
        'FOOTBALL-DATA STANDINGS STATUS '
        '[$competitionId]: '
        '${response.statusCode}',
      );

      return const [];
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final standings = decoded['standings'];

    if (standings is! List) {
      return const [];
    }

    final rows = <Map<String, dynamic>>[];

    for (final standing in standings) {
      if (standing is! Map<String, dynamic>) {
        continue;
      }

      final table = standing['table'];

      if (table is! List) {
        continue;
      }

      for (final row in table) {
        if (row is Map<String, dynamic>) {
          rows.add(row);
        }
      }
    }

    return rows;
  }

  Map<String, dynamic> _findStandingRow(
    List<Map<String, dynamic>> rows,
    int teamId,
  ) {
    for (final row in rows) {
      final team = _asMap(row['team']);

      if (_toInt(team['id']) == teamId) {
        return Map<String, dynamic>.from(row);
      }
    }

    return {};
  }

  // ============================================================
  // RATE LIMIT
  // ============================================================

  Future<http.Response?> _queuedGet(Uri uri) async {
    final previous = _requestQueue;
    final release = Completer<void>();

    _requestQueue = release.future;

    await previous;

    try {
      final last = _lastRequestAt;

      if (last != null) {
        final elapsed = DateTime.now().difference(last);

        final remaining = _minimumRequestGap - elapsed;

        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }

      print('FOOTBALL-DATA GET: $uri');

      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      _lastRequestAt = DateTime.now();

      if (response.statusCode == 429) {
        print('FOOTBALL-DATA RATE LIMIT: 429');
      }

      return response;
    } on TimeoutException {
      print('FOOTBALL-DATA TIMEOUT');
      return null;
    } catch (e) {
      print('FOOTBALL-DATA REQUEST ERROR: $e');
      return null;
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
    }
  }

  // ============================================================
  // NORMALIZZAZIONE NOMI
  // ============================================================

  double _matchConfidence(
    String homeA,
    String homeB,
    String awayA,
    String awayB,
  ) {
    return ((_teamSimilarity(homeA, homeB) + _teamSimilarity(awayA, awayB)) / 2)
        .clamp(0.0, 1.0);
  }

  double _teamSimilarity(String a, String b) {
    final left = _normalizeTeamName(a);
    final right = _normalizeTeamName(b);

    if (left.isEmpty || right.isEmpty) {
      return 0;
    }

    if (left == right) {
      return 1.0;
    }

    if ((left.contains(right) || right.contains(left)) &&
        (left.length >= 5 || right.length >= 5)) {
      return 0.92;
    }

    final leftTokens = left.split(' ').toSet();
    final rightTokens = right.split(' ').toSet();

    final intersection = leftTokens.intersection(rightTokens).length;

    final union = leftTokens.union(rightTokens).length;

    if (union == 0) {
      return 0;
    }

    final jaccard = intersection / union;

    final firstTokenBonus = leftTokens.first == rightTokens.first ? 0.08 : 0.0;

    return (jaccard + firstTokenBonus).clamp(0.0, 1.0);
  }

  String _normalizeTeamName(String value) {
    var text = _removeDiacritics(value.toLowerCase());

    text = text
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    final aliases = <String, String>{
      'internazionale': 'inter',
      'internazionale milano': 'inter milan',
      'man utd': 'manchester united',
      'man united': 'manchester united',
      'man city': 'manchester city',
      'bayern munchen': 'bayern munich',
      'paris saint germain': 'psg',
      'paris sg': 'psg',
      'tottenham hotspur': 'tottenham',
      'athletic club': 'athletic bilbao',
    };

    for (final entry in aliases.entries) {
      if (text == entry.key) {
        text = entry.value;
        break;
      }
    }

    const stopWords = <String>{
      'fc',
      'cf',
      'ac',
      'afc',
      'sc',
      'as',
      'ss',
      'cd',
      'ca',
      'club',
      'calcio',
      'football',
      'futbol',
      'futebol',
      'de',
      'the',
    };

    final tokens = text
        .split(' ')
        .where((token) => token.isNotEmpty && !stopWords.contains(token))
        .toList();

    return tokens.join(' ');
  }

  String _removeDiacritics(String value) {
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'æ': 'ae',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ø': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'ß': 'ss',
    };

    var result = value;

    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    return result;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return {};
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  void dispose() {
    _client.close();
  }
}
