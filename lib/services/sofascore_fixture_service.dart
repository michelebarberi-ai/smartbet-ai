import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/match_model.dart';

class SofaScoreFixtureService {
  final http.Client _client;

  SofaScoreFixtureService({
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String _baseUrl =
      'https://www.sofascore.com/api/v1';

  Map<String, String> get _headers {
    return {
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0',
    };
  }

  // ============================================================
  // PROSSIME PARTITE
  // ============================================================

  Future<List<MatchModel>> getUpcomingMatches({
    int days = 7,
  }) async {
    final now = DateTime.now();

    final matches = <MatchModel>[];

    print('');
    print('========================================');
    print('SMARTBET - SOFASCORE FIXTURES');
    print('========================================');
    print('Ricerca prossimi $days giorni');

    for (int offset = 0; offset < days; offset++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(
        Duration(days: offset),
      );

      final events =
          await _getDailyEvents(date);

      print('');
      print(
        '${_dateString(date)}: '
        '${events.length} eventi',
      );

      for (final event in events) {
        final match =
            _eventToMatch(event);

        if (match == null) {
          continue;
        }

        final matchDate =
            DateTime.tryParse(match.date);

        if (matchDate == null) {
          continue;
        }

        // ------------------------------------------------------
        // SOLO PARTITE FUTURE
        // ------------------------------------------------------

        if (!matchDate.isAfter(DateTime.now())) {
          continue;
        }

        matches.add(match);
      }
    }

    // ==========================================================
    // ORDINE CRONOLOGICO
    // ==========================================================

    matches.sort(
      (a, b) {
        final dateA =
            DateTime.tryParse(a.date);

        final dateB =
            DateTime.tryParse(b.date);

        if (dateA == null && dateB == null) {
          return 0;
        }

        if (dateA == null) {
          return 1;
        }

        if (dateB == null) {
          return -1;
        }

        return dateA.compareTo(dateB);
      },
    );

    print('');
    print('========================================');
    print(
      'PARTITE FUTURE TROVATE: '
      '${matches.length}',
    );
    print('========================================');

    return matches;
  }

  // ============================================================
  // PARTITE DI UNA SQUADRA
  // ============================================================

  Future<List<MatchModel>> getUpcomingMatchesForTeam({
    required String teamName,
    int days = 14,
  }) async {
    final allMatches =
        await getUpcomingMatches(
      days: days,
    );

    final normalizedRequested =
        _normalizeTeamName(teamName);

    return allMatches.where(
      (match) {
        final home =
            _normalizeTeamName(
          match.homeTeam,
        );

        final away =
            _normalizeTeamName(
          match.awayTeam,
        );

        return home == normalizedRequested ||
            away == normalizedRequested ||
            home.contains(normalizedRequested) ||
            away.contains(normalizedRequested) ||
            normalizedRequested.contains(home) ||
            normalizedRequested.contains(away);
      },
    ).toList();
  }

  // ============================================================
  // EVENTI DEL GIORNO
  // ============================================================

  Future<List<Map<String, dynamic>>> _getDailyEvents(
    DateTime date,
  ) async {
    final dateString =
        _dateString(date);

    final uri = Uri.parse(
      '$_baseUrl/sport/football/'
      'scheduled-events/$dateString',
    );

    try {
      final response =
          await _client.get(
        uri,
        headers: _headers,
      );

      print(
        'SOFASCORE $dateString '
        'STATUS: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        return [];
      }

      final decoded =
          jsonDecode(response.body);

      if (decoded
          is! Map<String, dynamic>) {
        return [];
      }

      final events =
          decoded['events'];

      if (events is! List) {
        return [];
      }

      return events
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      print(
        'SOFASCORE FIXTURE EXCEPTION: $e',
      );

      return [];
    }
  }

  // ============================================================
  // EVENTO → MATCH MODEL
  // ============================================================

  MatchModel? _eventToMatch(
    Map<String, dynamic> event,
  ) {
    final eventId =
        _toInt(event['id']);

    if (eventId <= 0) {
      return null;
    }

    final home =
        event['homeTeam'];

    final away =
        event['awayTeam'];

    if (home is! Map<String, dynamic> ||
        away is! Map<String, dynamic>) {
      return null;
    }

    final homeName =
        home['name']?.toString().trim() ?? '';

    final awayName =
        away['name']?.toString().trim() ?? '';

    if (homeName.isEmpty ||
        awayName.isEmpty) {
      return null;
    }

    final homeId =
        _toInt(home['id']);

    final awayId =
        _toInt(away['id']);

    // ==========================================================
    // DATA
    // ==========================================================

    final timestamp =
        _toInt(event['startTimestamp']);

    if (timestamp <= 0) {
      return null;
    }

    final startTime =
        DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    );

    // ==========================================================
    // COMPETIZIONE
    // ==========================================================

    String leagueName = '';
    int leagueId = 0;

    String country = '';

    final tournament =
        event['tournament'];

    if (tournament
        is Map<String, dynamic>) {
      leagueName =
          tournament['name']
                  ?.toString() ??
              '';

      leagueId =
          _toInt(
        tournament['id'],
      );

      final category =
          tournament['category'];

      if (category
          is Map<String, dynamic>) {
        country =
            category['name']
                    ?.toString() ??
                '';
      }
    }

    // ==========================================================
    // CLASSIFICAZIONE COMPETIZIONE
    // ==========================================================

    final lowerLeague =
        leagueName.toLowerCase();

    bool isFriendly = false;
    bool isEuropeanCup = false;
    bool isNational = false;

    String leagueType = 'domestic';

    double aiWeight = 0.70;

    if (lowerLeague.contains('friendly')) {
      isFriendly = true;
      leagueType = 'friendly';
      aiWeight = 0.60;
    }

    if (lowerLeague.contains('champions league') ||
        lowerLeague.contains('europa league') ||
        lowerLeague.contains('conference league')) {
      isEuropeanCup = true;
      leagueType = 'europeanCup';
      aiWeight = 0.90;
    }

    if (lowerLeague.contains('world cup') ||
        lowerLeague.contains('nations league') ||
        lowerLeague.contains('european championship')) {
      isNational = true;
      leagueType = 'national';
      aiWeight = 0.90;
    }

    // ==========================================================
    // MATCH MODEL
    // ==========================================================

    return MatchModel(
      fixtureId: eventId,

      homeTeamId: homeId,
      awayTeamId: awayId,

      homeTeam: homeName,
      awayTeam: awayName,

      league: leagueName,
      leagueId: leagueId,

      country: country,
      countryCode: '',

      date:
          startTime.toIso8601String(),

      leagueType: leagueType,

      isEuropeanCup: isEuropeanCup,
      isFriendly: isFriendly,
      isNational: isNational,

      aiWeight: aiWeight,

      smartScore: 0,

      homeWin: 0,
      draw: 0,
      awayWin: 0,

      valueBet: '',

      odd: 0,
    );
  }

  // ============================================================
  // DATA
  // ============================================================

  String _dateString(
    DateTime date,
  ) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // NORMALIZZAZIONE
  // ============================================================

  String _normalizeTeamName(
    String value,
  ) {
    var result =
        value.toLowerCase().trim();

    result = result
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');

    result = result
        .replaceAll(
          RegExp(r'\bfc\b'),
          '',
        )
        .replaceAll(
          RegExp(r'\bac\b'),
          '',
        )
        .replaceAll(
          RegExp(r'\bcalcio\b'),
          '',
        )
        .replaceAll(
          RegExp(r'[^a-z0-9 ]'),
          ' ',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();

    return result;
  }

  // ============================================================
  // CONVERSIONE
  // ============================================================

  int _toInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _client.close();
  }
}