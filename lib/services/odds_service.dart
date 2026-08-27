import 'dart:convert';

import 'package:http/http.dart' as http;

// ============================================================
// SINGOLA QUOTA MIGLIORE
// ============================================================

class BestOdd {
  final String outcome;
  final double odd;
  final int bookmakerId;
  final String bookmakerName;

  const BestOdd({
    required this.outcome,
    required this.odd,
    required this.bookmakerId,
    required this.bookmakerName,
  });
}

// ============================================================
// MERCATO COMPLETO DI UN BOOKMAKER - 1X2
// ============================================================

class BookmakerOdds {
  final int fixtureId;
  final int bookmakerId;
  final String bookmakerName;
  final double homeOdd;
  final double drawOdd;
  final double awayOdd;
  final DateTime? updatedAt;

  const BookmakerOdds({
    required this.fixtureId,
    required this.bookmakerId,
    required this.bookmakerName,
    required this.homeOdd,
    required this.drawOdd,
    required this.awayOdd,
    required this.updatedAt,
  });

  bool get isComplete => homeOdd > 1 && drawOdd > 1 && awayOdd > 1;

  double get rawHomeProbability => homeOdd > 1 ? 1 / homeOdd : 0;
  double get rawDrawProbability => drawOdd > 1 ? 1 / drawOdd : 0;
  double get rawAwayProbability => awayOdd > 1 ? 1 / awayOdd : 0;

  double get overround {
    if (!isComplete) return 0;
    return rawHomeProbability + rawDrawProbability + rawAwayProbability;
  }

  double get bookmakerMargin {
    if (!isComplete) return 0;
    return overround - 1;
  }

  double get fairHomeProbability =>
      overround > 0 ? rawHomeProbability / overround : 0;

  double get fairDrawProbability =>
      overround > 0 ? rawDrawProbability / overround : 0;

  double get fairAwayProbability =>
      overround > 0 ? rawAwayProbability / overround : 0;
}

// ============================================================
// RISULTATO COMPLETO 1X2
// ============================================================

class MatchOdds {
  final int fixtureId;
  final BookmakerOdds referenceMarket;
  final BestOdd bestHome;
  final BestOdd bestDraw;
  final BestOdd bestAway;
  final int bookmakerCount;

  const MatchOdds({
    required this.fixtureId,
    required this.referenceMarket,
    required this.bestHome,
    required this.bestDraw,
    required this.bestAway,
    required this.bookmakerCount,
  });

  bool get isComplete =>
      referenceMarket.isComplete &&
      bestHome.odd > 1 &&
      bestDraw.odd > 1 &&
      bestAway.odd > 1;

  double get overround => referenceMarket.overround;
  double get bookmakerMargin => referenceMarket.bookmakerMargin;
  double get fairHomeProbability => referenceMarket.fairHomeProbability;
  double get fairDrawProbability => referenceMarket.fairDrawProbability;
  double get fairAwayProbability => referenceMarket.fairAwayProbability;
}

// ============================================================
// QUOTE MULTI-MERCATO SMARTBET
// ============================================================

class FixtureMarketOdds {
  final int fixtureId;
  final MatchOdds? matchWinner;
  final Map<String, BestOdd> bestByOutcome;
  final int bookmakerCount;

  const FixtureMarketOdds({
    required this.fixtureId,
    required this.matchWinner,
    required this.bestByOutcome,
    required this.bookmakerCount,
  });

  BestOdd? oddFor(String outcome) {
    final key = _normalizeOutcomeStatic(outcome);
    return bestByOutcome[key];
  }

  static String _normalizeOutcomeStatic(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll('OVER ', 'OVER ')
        .replaceAll('UNDER ', 'UNDER ');
  }
}

// ============================================================
// ODDS SERVICE
// ============================================================

class OddsService {
  final http.Client _client;

  OddsService({http.Client? client}) : _client = client ?? http.Client();

  static final Map<int, FixtureMarketOdds?> _marketCache = {};

  // ============================================================
  // COMPATIBILITÀ: 1X2
  // ============================================================

  Future<MatchOdds?> getMatchWinnerOdds({required int fixtureId}) async {
    final all = await getFixtureMarketOdds(fixtureId: fixtureId);
    return all?.matchWinner;
  }

  // ============================================================
  // TUTTI I MERCATI UTILI A SMARTBET
  // ============================================================

  Future<FixtureMarketOdds?> getFixtureMarketOdds({
    required int fixtureId,
  }) async {
    if (fixtureId <= 0) {
      return null;
    }

    if (_marketCache.containsKey(fixtureId)) {
      return _marketCache[fixtureId];
    }

    final uri = Uri.parse(
      'https://smartbet-ai-y6gw.onrender.com/football/odds',
    ).replace(queryParameters: {'fixture': fixtureId.toString()});

    try {
      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('ODDS API ERROR: $errors');
        return null;
      }

      final responseData = decoded['response'];

      if (responseData is! List || responseData.isEmpty) {
        print('QUOTE PRE-MATCH NON DISPONIBILI');
        return null;
      }

      final matchWinnerMarkets = <BookmakerOdds>[];
      final bestByOutcome = <String, BestOdd>{};
      final bookmakerIds = <int>{};

      for (final responseItem in responseData) {
        if (responseItem is! Map<String, dynamic>) {
          continue;
        }

        DateTime? updatedAt;
        final update = responseItem['update']?.toString();

        if (update != null && update.isNotEmpty) {
          updatedAt = DateTime.tryParse(update);
        }

        final bookmakers = responseItem['bookmakers'];

        if (bookmakers is! List) {
          continue;
        }

        for (final bookmakerItem in bookmakers) {
          if (bookmakerItem is! Map<String, dynamic>) {
            continue;
          }

          final bookmakerId = _toInt(bookmakerItem['id']);
          final bookmakerName =
              bookmakerItem['name']?.toString().trim().isNotEmpty == true
              ? bookmakerItem['name'].toString().trim()
              : 'Bookmaker $bookmakerId';

          if (bookmakerId > 0) {
            bookmakerIds.add(bookmakerId);
          }

          final bets = bookmakerItem['bets'];

          if (bets is! List) {
            continue;
          }

          for (final betItem in bets) {
            if (betItem is! Map<String, dynamic>) {
              continue;
            }

            final betName = betItem['name']?.toString().trim() ?? '';
            final betId = _toInt(betItem['id']);
            final values = betItem['values'];

            if (values is! List) {
              continue;
            }

            // ------------------------------------------------------
            // MATCH WINNER 1X2
            // ------------------------------------------------------
            if (_isMatchWinnerBet(betId, betName)) {
              double homeOdd = 0;
              double drawOdd = 0;
              double awayOdd = 0;

              for (final valueItem in values) {
                if (valueItem is! Map<String, dynamic>) {
                  continue;
                }

                final label =
                    valueItem['value']?.toString().trim().toLowerCase() ?? '';
                final odd = _toDouble(valueItem['odd']);

                if (odd <= 1) {
                  continue;
                }

                if (label == 'home' || label == '1') {
                  homeOdd = odd;
                  _setBest(
                    bestByOutcome,
                    outcome: '1',
                    odd: odd,
                    bookmakerId: bookmakerId,
                    bookmakerName: bookmakerName,
                  );
                } else if (label == 'draw' || label == 'x') {
                  drawOdd = odd;
                  _setBest(
                    bestByOutcome,
                    outcome: 'X',
                    odd: odd,
                    bookmakerId: bookmakerId,
                    bookmakerName: bookmakerName,
                  );
                } else if (label == 'away' || label == '2') {
                  awayOdd = odd;
                  _setBest(
                    bestByOutcome,
                    outcome: '2',
                    odd: odd,
                    bookmakerId: bookmakerId,
                    bookmakerName: bookmakerName,
                  );
                }
              }

              final market = BookmakerOdds(
                fixtureId: fixtureId,
                bookmakerId: bookmakerId,
                bookmakerName: bookmakerName,
                homeOdd: homeOdd,
                drawOdd: drawOdd,
                awayOdd: awayOdd,
                updatedAt: updatedAt,
              );

              if (market.isComplete) {
                matchWinnerMarkets.add(market);
              }

              continue;
            }

            // ------------------------------------------------------
            // DOUBLE CHANCE
            // ------------------------------------------------------
            if (_isDoubleChanceBet(betId, betName)) {
              for (final valueItem in values) {
                if (valueItem is! Map<String, dynamic>) {
                  continue;
                }

                final raw = valueItem['value']?.toString() ?? '';
                final odd = _toDouble(valueItem['odd']);

                if (odd <= 1) {
                  continue;
                }

                final outcome = _doubleChanceOutcome(raw);

                if (outcome == null) {
                  continue;
                }

                _setBest(
                  bestByOutcome,
                  outcome: outcome,
                  odd: odd,
                  bookmakerId: bookmakerId,
                  bookmakerName: bookmakerName,
                );
              }

              continue;
            }

            // ------------------------------------------------------
            // OVER / UNDER GOALS
            // ------------------------------------------------------
            if (_isGoalsOverUnderBet(betId, betName)) {
              for (final valueItem in values) {
                if (valueItem is! Map<String, dynamic>) {
                  continue;
                }

                final raw = valueItem['value']?.toString() ?? '';
                final odd = _toDouble(valueItem['odd']);

                if (odd <= 1) {
                  continue;
                }

                final outcome = _goalsOutcome(raw, betName);

                if (outcome == null) {
                  continue;
                }

                if (outcome == 'OVER 1.5' ||
                    outcome == 'UNDER 1.5' ||
                    outcome == 'OVER 2.5' ||
                    outcome == 'UNDER 2.5') {
                  _setBest(
                    bestByOutcome,
                    outcome: outcome,
                    odd: odd,
                    bookmakerId: bookmakerId,
                    bookmakerName: bookmakerName,
                  );
                }
              }

              continue;
            }

            // ------------------------------------------------------
            // BOTH TEAMS TO SCORE
            // ------------------------------------------------------
            if (_isBothTeamsScoreBet(betId, betName)) {
              for (final valueItem in values) {
                if (valueItem is! Map<String, dynamic>) {
                  continue;
                }

                final raw = valueItem['value']?.toString() ?? '';
                final odd = _toDouble(valueItem['odd']);

                if (odd <= 1) {
                  continue;
                }

                final outcome = _bothTeamsOutcome(raw);

                if (outcome == null) {
                  continue;
                }

                _setBest(
                  bestByOutcome,
                  outcome: outcome,
                  odd: odd,
                  bookmakerId: bookmakerId,
                  bookmakerName: bookmakerName,
                );
              }
            }
          }
        }
      }

      MatchOdds? matchWinner;

      if (matchWinnerMarkets.isNotEmpty) {
        final uniqueMarkets = <int, BookmakerOdds>{};

        for (final market in matchWinnerMarkets) {
          final existing = uniqueMarkets[market.bookmakerId];

          if (existing == null) {
            uniqueMarkets[market.bookmakerId] = market;
            continue;
          }

          final currentUpdate = market.updatedAt;
          final oldUpdate = existing.updatedAt;

          if (currentUpdate != null &&
              (oldUpdate == null || currentUpdate.isAfter(oldUpdate))) {
            uniqueMarkets[market.bookmakerId] = market;
          }
        }

        final finalMarkets = uniqueMarkets.values.toList()
          ..sort((a, b) => a.overround.compareTo(b.overround));

        final referenceMarket = finalMarkets.first;

        final bestHome = bestByOutcome['1'];
        final bestDraw = bestByOutcome['X'];
        final bestAway = bestByOutcome['2'];

        if (bestHome != null && bestDraw != null && bestAway != null) {
          matchWinner = MatchOdds(
            fixtureId: fixtureId,
            referenceMarket: referenceMarket,
            bestHome: bestHome,
            bestDraw: bestDraw,
            bestAway: bestAway,
            bookmakerCount: finalMarkets.length,
          );
        }
      }

      final result = FixtureMarketOdds(
        fixtureId: fixtureId,
        matchWinner: matchWinner,
        bestByOutcome: Map.unmodifiable(bestByOutcome),
        bookmakerCount: bookmakerIds.length,
      );

      print('');
      print('========================================');
      print('SMARTBET - QUOTE MULTI-MERCATO');
      print('========================================');

      for (final key in [
        '1',
        'X',
        '2',
        '1X',
        'X2',
        '12',
        'OVER 1.5',
        'UNDER 1.5',
        'OVER 2.5',
        'UNDER 2.5',
        'GOAL',
        'NO GOAL',
      ]) {
        final odd = result.oddFor(key);

        if (odd != null) {
          print('$key: ${odd.odd.toStringAsFixed(2)} - ${odd.bookmakerName}');
        }
      }

      print('========================================');

      _marketCache[fixtureId] = result;
      return result;
    } catch (e) {
      print('SMARTBET ODDS EXCEPTION: $e');
      return null;
    }
  }

  // ============================================================
  // HELPERS MERCATI
  // ============================================================

  void _setBest(
    Map<String, BestOdd> map, {
    required String outcome,
    required double odd,
    required int bookmakerId,
    required String bookmakerName,
  }) {
    final key = _normalizeOutcome(outcome);
    final existing = map[key];

    if (existing == null || odd > existing.odd) {
      map[key] = BestOdd(
        outcome: key,
        odd: odd,
        bookmakerId: bookmakerId,
        bookmakerName: bookmakerName,
      );
    }
  }

  bool _isMatchWinnerBet(int betId, String betName) {
    // API-Football pre-match: Bet ID 1 = Match Winner.
    // Il fallback sul nome serve solo per compatibilita se l'id non arriva.
    if (betId > 0) {
      return betId == 1;
    }

    final normalized = _normalizeText(betName);
    return normalized == 'match winner';
  }

  bool _isDoubleChanceBet(int betId, String betName) {
    // API-Football pre-match: Bet ID 12 = Double Chance.
    if (betId > 0) {
      return betId == 12;
    }

    return _normalizeText(betName) == 'double chance';
  }

  bool _isGoalsOverUnderBet(int betId, String betName) {
    // API-Football pre-match:
    // 5  = Goals Over/Under FULL TIME
    // 6  = Goals Over/Under First Half
    // 26 = Goals Over/Under Second Half
    // Usiamo quindi l'ID 5 per evitare qualunque sotto-mercato.
    if (betId > 0) {
      return betId == 5;
    }

    return _normalizeText(betName) == 'goals over under';
  }

  bool _isBothTeamsScoreBet(int betId, String betName) {
    // API-Football pre-match: Bet ID 8 = Both Teams Score.
    if (betId > 0) {
      return betId == 8;
    }

    final normalized = _normalizeText(betName);
    return normalized == 'both teams score' ||
        normalized == 'both teams to score';
  }

  String? _doubleChanceOutcome(String raw) {
    final value = _normalizeText(
      raw,
    ).replaceAll(' ', '').replaceAll('/', '').replaceAll('-', '');

    if (value == '1x' ||
        value == 'homedraw' ||
        value == 'drawhome' ||
        value == 'homeordraw') {
      return '1X';
    }

    if (value == 'x2' ||
        value == 'drawaway' ||
        value == 'awaydraw' ||
        value == 'draworaway') {
      return 'X2';
    }

    if (value == '12' ||
        value == 'homeaway' ||
        value == 'awayhome' ||
        value == 'homeoraway') {
      return '12';
    }

    return null;
  }

  String? _goalsOutcome(String raw, String betName) {
    // La linea deve provenire dal VALUE del mercato, non dal nome del bet.
    // Questo riduce il rischio di confondere mercati secondari con il
    // totale gol full-time principale.
    final value = _normalizeText(raw);

    final isOver = value.contains('over');
    final isUnder = value.contains('under');

    if (!isOver && !isUnder) {
      return null;
    }

    final number = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(value);

    if (number == null) {
      return null;
    }

    final line = number.group(1);

    if (line != '1.5' && line != '2.5') {
      return null;
    }

    return '${isOver ? 'OVER' : 'UNDER'} $line';
  }

  String? _bothTeamsOutcome(String raw) {
    final value = _normalizeText(raw);

    if (value == 'yes' ||
        value == 'si' ||
        value == 'goal' ||
        value == 'both teams score yes') {
      return 'GOAL';
    }

    if (value == 'no' || value == 'no goal' || value == 'both teams score no') {
      return 'NO GOAL';
    }

    return null;
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeOutcome(String value) {
    return value.trim().toUpperCase();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static void clearCache() {
    _marketCache.clear();
  }

  void dispose() {
    _client.close();
  }
}
