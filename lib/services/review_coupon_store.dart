import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/match_model.dart';

class ReviewCouponStore {
  static const String storageKey = 'review_coupon_selections_v1';
  static const int maximumSelections = 12;

  static Future<bool> containsFixture(int fixtureId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);

    if (raw == null || raw.isEmpty) {
      return false;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return false;
      }

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final map = Map<String, dynamic>.from(item);
        final match = map['match'];

        if (match is Map && match['fixtureId'] == fixtureId) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  static Future<int> count() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);

    if (raw == null || raw.isEmpty) {
      return 0;
    }

    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<String> addMatch(
    MatchModel match, {
    String market = '1',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);

    List<dynamic> data = [];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is List) {
          data = List<dynamic>.from(decoded);
        }
      } catch (_) {
        data = [];
      }
    }

    for (final item in data) {
      if (item is! Map) {
        continue;
      }

      final storedMatch = item['match'];

      if (storedMatch is Map && storedMatch['fixtureId'] == match.fixtureId) {
        return 'duplicate';
      }
    }

    if (data.length >= maximumSelections) {
      return 'full';
    }

    data.add({'match': _matchToJson(match), 'market': market});

    await prefs.setString(storageKey, jsonEncode(data));

    return 'added';
  }

  static Map<String, dynamic> _matchToJson(MatchModel match) {
    return {
      'fixtureId': match.fixtureId,
      'homeTeamId': match.homeTeamId,
      'awayTeamId': match.awayTeamId,
      'homeTeam': match.homeTeam,
      'awayTeam': match.awayTeam,
      'league': match.league,
      'leagueId': match.leagueId,
      'country': match.country,
      'countryCode': match.countryCode,
      'date': match.date,
      'leagueType': match.leagueType,
      'isEuropeanCup': match.isEuropeanCup,
      'isFriendly': match.isFriendly,
      'isNational': match.isNational,
      'aiWeight': match.aiWeight,
      'smartScore': match.smartScore,
      'homeWin': match.homeWin,
      'draw': match.draw,
      'awayWin': match.awayWin,
      'valueBet': match.valueBet,
      'odd': match.odd,
    };
  }
}
