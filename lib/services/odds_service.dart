import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_rate_limiter.dart';

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
// MERCATO COMPLETO DI UN BOOKMAKER
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

  bool get isComplete {
    return homeOdd > 1 && drawOdd > 1 && awayOdd > 1;
  }

  double get rawHomeProbability {
    if (homeOdd <= 1) {
      return 0;
    }

    return 1 / homeOdd;
  }

  double get rawDrawProbability {
    if (drawOdd <= 1) {
      return 0;
    }

    return 1 / drawOdd;
  }

  double get rawAwayProbability {
    if (awayOdd <= 1) {
      return 0;
    }

    return 1 / awayOdd;
  }

  double get overround {
    if (!isComplete) {
      return 0;
    }

    return rawHomeProbability + rawDrawProbability + rawAwayProbability;
  }

  double get bookmakerMargin {
    if (!isComplete) {
      return 0;
    }

    return overround - 1;
  }

  double get fairHomeProbability {
    if (overround <= 0) {
      return 0;
    }

    return rawHomeProbability / overround;
  }

  double get fairDrawProbability {
    if (overround <= 0) {
      return 0;
    }

    return rawDrawProbability / overround;
  }

  double get fairAwayProbability {
    if (overround <= 0) {
      return 0;
    }

    return rawAwayProbability / overround;
  }
}

// ============================================================
// RISULTATO COMPLETO QUOTE SMARTBET
// ============================================================

class MatchOdds {
  final int fixtureId;

  // ----------------------------------------------------------
  // MERCATO DI RIFERIMENTO
  // ----------------------------------------------------------
  //
  // Utilizzato esclusivamente per:
  //
  // - overround;
  // - margine bookmaker;
  // - probabilità fair.
  //
  // Le sue tre quote appartengono allo stesso bookmaker.
  // ----------------------------------------------------------

  final BookmakerOdds referenceMarket;

  // ----------------------------------------------------------
  // BEST ODDS
  // ----------------------------------------------------------

  final BestOdd bestHome;

  final BestOdd bestDraw;

  final BestOdd bestAway;

  // ----------------------------------------------------------
  // NUMERO BOOKMAKER
  // ----------------------------------------------------------

  final int bookmakerCount;

  const MatchOdds({
    required this.fixtureId,
    required this.referenceMarket,
    required this.bestHome,
    required this.bestDraw,
    required this.bestAway,
    required this.bookmakerCount,
  });

  bool get isComplete {
    return referenceMarket.isComplete &&
        bestHome.odd > 1 &&
        bestDraw.odd > 1 &&
        bestAway.odd > 1;
  }

  double get overround {
    return referenceMarket.overround;
  }

  double get bookmakerMargin {
    return referenceMarket.bookmakerMargin;
  }

  double get fairHomeProbability {
    return referenceMarket.fairHomeProbability;
  }

  double get fairDrawProbability {
    return referenceMarket.fairDrawProbability;
  }

  double get fairAwayProbability {
    return referenceMarket.fairAwayProbability;
  }
}

// ============================================================
// ODDS SERVICE
// ============================================================

class OddsService {
  final http.Client _client;

  OddsService({http.Client? client}) : _client = client ?? http.Client();

  // ============================================================
  // CACHE
  // ============================================================

  static final Map<int, MatchOdds?> _cache = {};

  // ============================================================
  // RECUPERO QUOTE
  // ============================================================

  Future<MatchOdds?> getMatchWinnerOdds({required int fixtureId}) async {
    if (fixtureId <= 0) {
      print('');
      print('SMARTBET ODDS: fixture ID non valido');

      return null;
    }

    if (_cache.containsKey(fixtureId)) {
      print('');
      print('SMARTBET ODDS CACHE HIT');
      print('Fixture ID: $fixtureId');

      return _cache[fixtureId];
    }

    print('');
    print('========================================');
    print('SMARTBET - ODDS SERVICE');
    print('========================================');

    print('Fixture ID: $fixtureId');

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/odds',
    ).replace(queryParameters: {'fixture': fixtureId.toString()});

    print('URL: $uri');

    try {
      await ApiRateLimiter.wait();

      final response = await _client.get(uri, headers: _headers);

      print('ODDS STATUS: ${response.statusCode}');

      if (response.statusCode != 200) {
        _cache[fixtureId] = null;

        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        _cache[fixtureId] = null;

        return null;
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        print('ODDS API ERROR:');
        print(errors);

        _cache[fixtureId] = null;

        return null;
      }

      final responseData = decoded['response'];

      if (responseData is! List || responseData.isEmpty) {
        print('QUOTE PRE-MATCH NON DISPONIBILI');

        _cache[fixtureId] = null;

        return null;
      }

      final markets = <BookmakerOdds>[];

      // ========================================================
      // PARSING RISPOSTA
      // ========================================================

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

        // ======================================================
        // BOOKMAKER
        // ======================================================

        for (final bookmakerItem in bookmakers) {
          if (bookmakerItem is! Map<String, dynamic>) {
            continue;
          }

          final bookmakerId = _toInt(bookmakerItem['id']);

          final bookmakerName = bookmakerItem['name']?.toString().trim() ?? '';

          final bets = bookmakerItem['bets'];

          if (bets is! List) {
            continue;
          }

          // ====================================================
          // MERCATO 1X2
          // ====================================================

          for (final betItem in bets) {
            if (betItem is! Map<String, dynamic>) {
              continue;
            }

            final betName = betItem['name']?.toString().trim() ?? '';

            if (!_isMatchWinnerBet(betName)) {
              continue;
            }

            final values = betItem['values'];

            if (values is! List) {
              continue;
            }

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
                continue;
              }

              if (label == 'draw' || label == 'x') {
                drawOdd = odd;
                continue;
              }

              if (label == 'away' || label == '2') {
                awayOdd = odd;
              }
            }

            final market = BookmakerOdds(
              fixtureId: fixtureId,
              bookmakerId: bookmakerId,
              bookmakerName: bookmakerName.isEmpty
                  ? 'Bookmaker $bookmakerId'
                  : bookmakerName,
              homeOdd: homeOdd,
              drawOdd: drawOdd,
              awayOdd: awayOdd,
              updatedAt: updatedAt,
            );

            if (market.isComplete) {
              markets.add(market);
            }
          }
        }
      }

      if (markets.isEmpty) {
        print('');
        print('NESSUN MERCATO 1X2 COMPLETO TROVATO');

        _cache[fixtureId] = null;

        return null;
      }

      // ========================================================
      // ELIMINA EVENTUALI DUPLICATI BOOKMAKER
      // ========================================================

      final uniqueMarkets = <int, BookmakerOdds>{};

      for (final market in markets) {
        final existing = uniqueMarkets[market.bookmakerId];

        if (existing == null) {
          uniqueMarkets[market.bookmakerId] = market;

          continue;
        }

        // Se abbiamo due record dello stesso bookmaker,
        // teniamo quello aggiornato più recentemente.

        final currentUpdate = market.updatedAt;

        final oldUpdate = existing.updatedAt;

        if (currentUpdate != null &&
            (oldUpdate == null || currentUpdate.isAfter(oldUpdate))) {
          uniqueMarkets[market.bookmakerId] = market;
        }
      }

      final finalMarkets = uniqueMarkets.values.toList();

      // ========================================================
      // MERCATO DI RIFERIMENTO
      // ========================================================
      //
      // IMPORTANTISSIMO:
      //
      // Le probabilità fair devono derivare
      // da quote dello STESSO bookmaker.
      //
      // Usiamo il bookmaker con l'overround più basso.
      // ========================================================

      finalMarkets.sort((a, b) => a.overround.compareTo(b.overround));

      final referenceMarket = finalMarkets.first;

      // ========================================================
      // BEST QUOTA 1
      // ========================================================

      final bestHomeMarket = finalMarkets.reduce(
        (current, next) => next.homeOdd > current.homeOdd ? next : current,
      );

      final bestHome = BestOdd(
        outcome: '1',
        odd: bestHomeMarket.homeOdd,
        bookmakerId: bestHomeMarket.bookmakerId,
        bookmakerName: bestHomeMarket.bookmakerName,
      );

      // ========================================================
      // BEST QUOTA X
      // ========================================================

      final bestDrawMarket = finalMarkets.reduce(
        (current, next) => next.drawOdd > current.drawOdd ? next : current,
      );

      final bestDraw = BestOdd(
        outcome: 'X',
        odd: bestDrawMarket.drawOdd,
        bookmakerId: bestDrawMarket.bookmakerId,
        bookmakerName: bestDrawMarket.bookmakerName,
      );

      // ========================================================
      // BEST QUOTA 2
      // ========================================================

      final bestAwayMarket = finalMarkets.reduce(
        (current, next) => next.awayOdd > current.awayOdd ? next : current,
      );

      final bestAway = BestOdd(
        outcome: '2',
        odd: bestAwayMarket.awayOdd,
        bookmakerId: bestAwayMarket.bookmakerId,
        bookmakerName: bestAwayMarket.bookmakerName,
      );

      // ========================================================
      // RISULTATO
      // ========================================================

      final result = MatchOdds(
        fixtureId: fixtureId,
        referenceMarket: referenceMarket,
        bestHome: bestHome,
        bestDraw: bestDraw,
        bestAway: bestAway,
        bookmakerCount: finalMarkets.length,
      );

      print('');
      print('========================================');
      print('SMARTBET - BEST ODDS');
      print('========================================');

      print(
        'Bookmaker analizzati: '
        '${result.bookmakerCount}',
      );

      print('');

      print('MERCATO FAIR DI RIFERIMENTO:');

      print(
        '${referenceMarket.bookmakerName} '
        '(ID ${referenceMarket.bookmakerId})',
      );

      print('1: ${referenceMarket.homeOdd}');

      print('X: ${referenceMarket.drawOdd}');

      print('2: ${referenceMarket.awayOdd}');

      print(
        'Overround: '
        '${referenceMarket.overround.toStringAsFixed(4)}',
      );

      print(
        'Margine: '
        '${(referenceMarket.bookmakerMargin * 100).toStringAsFixed(2)}%',
      );

      print('');

      print('MIGLIORE QUOTA 1:');
      print(
        '${bestHome.odd.toStringAsFixed(2)} '
        '- ${bestHome.bookmakerName}',
      );

      print('');

      print('MIGLIORE QUOTA X:');
      print(
        '${bestDraw.odd.toStringAsFixed(2)} '
        '- ${bestDraw.bookmakerName}',
      );

      print('');

      print('MIGLIORE QUOTA 2:');
      print(
        '${bestAway.odd.toStringAsFixed(2)} '
        '- ${bestAway.bookmakerName}',
      );

      print('========================================');

      _cache[fixtureId] = result;

      return result;
    } catch (e) {
      print('');
      print('SMARTBET ODDS EXCEPTION: $e');

      _cache[fixtureId] = null;

      return null;
    }
  }

  // ============================================================
  // IDENTIFICAZIONE MERCATO
  // ============================================================

  bool _isMatchWinnerBet(String betName) {
    final normalized = betName.toLowerCase().trim();

    return normalized == 'match winner' ||
        normalized == 'winner' ||
        normalized == '1x2' ||
        normalized.contains('match winner');
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

  double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
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
    _client.close();
  }
}
