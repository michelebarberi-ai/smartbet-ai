import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/match_model.dart';

class SofaScoreMatch {
  final int eventId;

  final String homeTeam;
  final String awayTeam;

  final DateTime? startTime;

  final String tournamentName;

  final int homeTeamId;
  final int awayTeamId;

  final double confidence;

  const SofaScoreMatch({
    required this.eventId,
    required this.homeTeam,
    required this.awayTeam,
    required this.startTime,
    required this.tournamentName,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.confidence,
  });

  bool get isReliable => confidence >= 0.85;
}

class SofaScoreMatchingService {
  final http.Client _client;

  SofaScoreMatchingService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://www.sofascore.com/api/v1';

  static final Map<String, SofaScoreMatch?> _cache = {};

  // ============================================================
  // MATCHING PRINCIPALE
  // ============================================================

  Future<SofaScoreMatch?> findMatch(MatchModel match) async {
    final cacheKey = '${match.homeTeam}|${match.awayTeam}|${match.date}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    final apiDate = DateTime.tryParse(match.date);

    if (apiDate == null) {
      _cache[cacheKey] = null;
      return null;
    }

    // ==========================================================
    // 1. CERCA GLI EVENTI DEL GIORNO
    // ==========================================================

    final dailyEvents = await _getDailyEvents(apiDate);

    final dailyMatch = _findBestMatch(match, dailyEvents);

    if (dailyMatch != null) {
      _cache[cacheKey] = dailyMatch;
      return dailyMatch;
    }

    // ==========================================================
    // 2. CERCA EVENTI DELLA SQUADRA DI CASA
    // ==========================================================

    final homeEvents = await _getTeamEvents(match.homeTeamId);

    final homeMatch = _findBestMatch(match, homeEvents);

    if (homeMatch != null) {
      _cache[cacheKey] = homeMatch;
      return homeMatch;
    }

    // ==========================================================
    // 3. CERCA EVENTI DELLA SQUADRA OSPITE
    // ==========================================================

    final awayEvents = await _getTeamEvents(match.awayTeamId);

    final awayMatch = _findBestMatch(match, awayEvents);

    if (awayMatch != null) {
      _cache[cacheKey] = awayMatch;
      return awayMatch;
    }

    // ==========================================================
    // NESSUN MATCH
    // ==========================================================

    _cache[cacheKey] = null;

    return null;
  }

  // ============================================================
  // EVENTI DEL GIORNO
  // ============================================================

  Future<List<Map<String, dynamic>>> _getDailyEvents(DateTime date) async {
    final dateString =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    final uri = Uri.parse(
      '$_baseUrl/sport/football/scheduled-events/$dateString',
    );

    try {
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final events = decoded['events'];

      if (events is! List) {
        return [];
      }

      return events.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // EVENTI DELLA SQUADRA
  // ============================================================

  Future<List<Map<String, dynamic>>> _getTeamEvents(int teamId) async {
    if (teamId <= 0) {
      return [];
    }

    final allEvents = <Map<String, dynamic>>[];

    // Proviamo alcune pagine degli eventi futuri.
    for (int page = 0; page < 3; page++) {
      final uri = Uri.parse('$_baseUrl/team/$teamId/events/next/$page');

      try {
        final response = await _client.get(uri, headers: _headers);

        if (response.statusCode != 200) {
          continue;
        }

        final decoded = jsonDecode(response.body);

        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final events = decoded['events'];

        if (events is! List) {
          continue;
        }

        for (final event in events) {
          if (event is Map<String, dynamic>) {
            allEvents.add(event);
          }
        }
      } catch (_) {
        continue;
      }
    }

    return allEvents;
  }

  // ============================================================
  // TROVA MIGLIOR PARTITA
  // ============================================================

  SofaScoreMatch? _findBestMatch(
    MatchModel apiMatch,
    List<Map<String, dynamic>> events,
  ) {
    SofaScoreMatch? bestMatch;

    double bestConfidence = 0;

    for (final event in events) {
      final candidate = _parseEvent(event);

      if (candidate == null) {
        continue;
      }

      final confidence = _calculateConfidence(apiMatch, candidate);

      if (confidence > bestConfidence) {
        bestConfidence = confidence;

        bestMatch = SofaScoreMatch(
          eventId: candidate.eventId,
          homeTeam: candidate.homeTeam,
          awayTeam: candidate.awayTeam,
          startTime: candidate.startTime,
          tournamentName: candidate.tournamentName,
          homeTeamId: candidate.homeTeamId,
          awayTeamId: candidate.awayTeamId,
          confidence: confidence,
        );
      }
    }

    // ==========================================================
    // SOGLIA DI SICUREZZA
    // ==========================================================

    if (bestMatch == null) {
      return null;
    }

    if (bestConfidence < 0.85) {
      return null;
    }

    return bestMatch;
  }

  // ============================================================
  // PARSING EVENTO
  // ============================================================

  SofaScoreMatch? _parseEvent(Map<String, dynamic> event) {
    final eventId = _toInt(event['id']);

    if (eventId <= 0) {
      return null;
    }

    final home = event['homeTeam'];

    final away = event['awayTeam'];

    if (home is! Map<String, dynamic>) {
      return null;
    }

    if (away is! Map<String, dynamic>) {
      return null;
    }

    final homeName = home['name']?.toString().trim() ?? '';

    final awayName = away['name']?.toString().trim() ?? '';

    if (homeName.isEmpty || awayName.isEmpty) {
      return null;
    }

    final homeId = _toInt(home['id']);

    final awayId = _toInt(away['id']);

    DateTime? startTime;

    final timestamp = _toInt(event['startTimestamp']);

    if (timestamp > 0) {
      startTime = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      ).toLocal();
    }

    String tournamentName = '';

    final tournament = event['tournament'];

    if (tournament is Map<String, dynamic>) {
      tournamentName = tournament['name']?.toString() ?? '';
    }

    return SofaScoreMatch(
      eventId: eventId,
      homeTeam: homeName,
      awayTeam: awayName,
      startTime: startTime,
      tournamentName: tournamentName,
      homeTeamId: homeId,
      awayTeamId: awayId,
      confidence: 0,
    );
  }

  // ============================================================
  // CALCOLO CONFIDENZA
  // ============================================================

  double _calculateConfidence(MatchModel apiMatch, SofaScoreMatch sofaMatch) {
    double score = 0;

    final apiHome = _normalizeTeamName(apiMatch.homeTeam);

    final apiAway = _normalizeTeamName(apiMatch.awayTeam);

    final sofaHome = _normalizeTeamName(sofaMatch.homeTeam);

    final sofaAway = _normalizeTeamName(sofaMatch.awayTeam);

    // ==========================================================
    // SQUADRA CASA
    // ==========================================================

    if (apiHome == sofaHome) {
      score += 0.35;
    } else if (_similarTeamNames(apiHome, sofaHome)) {
      score += 0.25;
    }

    // ==========================================================
    // SQUADRA OSPITE
    // ==========================================================

    if (apiAway == sofaAway) {
      score += 0.35;
    } else if (_similarTeamNames(apiAway, sofaAway)) {
      score += 0.25;
    }

    // ==========================================================
    // DATA
    // ==========================================================

    final apiDate = DateTime.tryParse(apiMatch.date);

    if (apiDate != null && sofaMatch.startTime != null) {
      final apiDay = DateTime(apiDate.year, apiDate.month, apiDate.day);

      final sofaDay = DateTime(
        sofaMatch.startTime!.year,
        sofaMatch.startTime!.month,
        sofaMatch.startTime!.day,
      );

      if (apiDay == sofaDay) {
        score += 0.15;
      }
    }

    // ==========================================================
    // ORARIO
    // ==========================================================

    if (apiDate != null && sofaMatch.startTime != null) {
      final difference = apiDate
          .difference(sofaMatch.startTime!)
          .inMinutes
          .abs();

      if (difference <= 10) {
        score += 0.15;
      } else if (difference <= 30) {
        score += 0.10;
      } else if (difference <= 120) {
        score += 0.05;
      }
    }

    return score.clamp(0.0, 1.0);
  }

  // ============================================================
  // NORMALIZZAZIONE NOMI
  // ============================================================

  String _normalizeTeamName(String value) {
    var result = value.toLowerCase().trim();

    // Accenti comuni
    result = result
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');

    // Sigle e denominazioni comuni
    result = result
        .replaceAll(RegExp(r'\bfc\b'), '')
        .replaceAll(RegExp(r'\bafc\b'), '')
        .replaceAll(RegExp(r'\bac\b'), '')
        .replaceAll(RegExp(r'\bsc\b'), '')
        .replaceAll(RegExp(r'\bcalcio\b'), '')
        .replaceAll(RegExp(r'\bfootball club\b'), '')
        .replaceAll(RegExp(r'\bclub\b'), '');

    result = result
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return result;
  }

  // ============================================================
  // CONFRONTO NOMI
  // ============================================================

  bool _similarTeamNames(String first, String second) {
    if (first.isEmpty || second.isEmpty) {
      return false;
    }

    if (first == second) {
      return true;
    }

    if (first.contains(second) || second.contains(first)) {
      return true;
    }

    final firstWords = first.split(' ');

    final secondWords = second.split(' ');

    int commonWords = 0;

    for (final word in firstWords) {
      if (word.length < 4) {
        continue;
      }

      if (secondWords.contains(word)) {
        commonWords++;
      }
    }

    return commonWords >= 1;
  }

  // ============================================================
  // HEADERS
  // ============================================================

  Map<String, String> get _headers {
    return const {
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 '
          '(iPhone; CPU iPhone OS 18_0 like Mac OS X) '
          'AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) '
          'Version/18.0 Mobile/15E148 Safari/604.1',
    };
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
