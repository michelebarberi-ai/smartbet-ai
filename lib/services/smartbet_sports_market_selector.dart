import 'goalvdline_quote_policy.dart';

/// Seleziona mercati usando esclusivamente probabilita sportive.
///
/// Le quote sono consultate soltanto dopo il ranking,
/// per verificare disponibilita e quota minima.
class SmartBetSportsMarketPick {
  final String market;
  final int probability;
  final double odd;

  const SmartBetSportsMarketPick({
    required this.market,
    required this.probability,
    required this.odd,
  });
}

/// Forecast made BEFORE checking any price. The model's best sporting
/// outcome never changes because of a quote.
class SmartBetSportsForecast {
  final String market;
  final int probability;
  const SmartBetSportsForecast(this.market, this.probability);
}

/// A sporting forecast and its separate, optionally playable coupon pick.
class SmartBetSportsRecommendation {
  final SmartBetSportsForecast primary;
  final double? primaryOdd;
  final SmartBetSportsMarketPick? couponPick;
  const SmartBetSportsRecommendation({
    required this.primary,
    this.primaryOdd,
    this.couponPick,
  });

  bool get usesAlternative =>
      couponPick != null && couponPick!.market != primary.market;
}

class SmartBetSportsMarketSelector {
  const SmartBetSportsMarketSelector._();

  static const double minimumOdd = GoalVdLineQuotePolicy.minimumOdd;

  static String _normalizeMarket(String value) {
    return value
        .toUpperCase()
        .replaceAll('BTTS YES', 'GOAL')
        .replaceAll('BTTS NO', 'NOGOAL')
        .replaceAll('NO GOAL', 'NOGOAL')
        .replaceAll('OVER', 'O')
        .replaceAll('UNDER', 'U')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Ranking indipendente da quote, edge ed expected value.
  static List<MapEntry<String, int>> rankedMarkets(
    Map<String, int> sportsProbabilities,
  ) {
    final ranked = sportsProbabilities.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty &&
              entry.value > 0 &&
              entry.value <= 100,
        )
        .toList();

    ranked.sort((a, b) {
      final probability = b.value.compareTo(a.value);
      if (probability != 0) return probability;

      // Spareggio deterministico, mai economico.
      return a.key.compareTo(b.key);
    });

    return List.unmodifiable(ranked);
  }

  /// Sports -> rank -> Sisal quote check. The primary is NEVER replaced
  /// by a quoted alternative: that option is exposed separately as couponPick.
  static SmartBetSportsRecommendation? recommend({
    required Map<String, int> sportsProbabilities,
    required Map<String, double> quotedOdds,
    Iterable<String> blockedMarkets = const <String>[],
    int minimumProbability = 65,
  }) {
    if (minimumProbability < 0 || minimumProbability > 100) {
      throw RangeError.range(minimumProbability, 0, 100, 'minimumProbability');
    }
    final blocked = blockedMarkets.map(_normalizeMarket).toSet();
    final ranked = rankedMarkets(sportsProbabilities)
        .where((entry) => !blocked.contains(_normalizeMarket(entry.key)))
        .toList(growable: false);
    if (ranked.isEmpty) return null;

    final top = ranked.first;
    final topOdd = quotedOdds[top.key];
    SmartBetSportsMarketPick? playable;

    // Highest sporting probability remains first, whether or not Sisal
    // quotes it. Only after that consider an alternative at >=threshold.
    for (final entry in ranked) {
      if (entry.value < minimumProbability) break;
      final odd = quotedOdds[entry.key];
      if (odd == null || !odd.isFinite || odd <= minimumOdd) continue;
      playable = SmartBetSportsMarketPick(
        market: entry.key, probability: entry.value, odd: odd,
      );
      break;
    }
    return SmartBetSportsRecommendation(
      primary: SmartBetSportsForecast(top.key, top.value),
      primaryOdd: topOdd != null && topOdd.isFinite && topOdd > 1 ? topOdd : null,
      couponPick: playable,
    );
  }

  /// Tutti i mercati effettivamente quotati e non bloccati dall'audit.
  /// Ordine sportivo prima del filtro quote, come bestPlayable originale.
  static List<SmartBetSportsMarketPick> allPlayable({
    required Map<String, int> sportsProbabilities,
    required Map<String, double> quotedOdds,
    Iterable<String> blockedMarkets = const <String>[],
    int minimumProbability = 0,
  }) {
    if (minimumProbability < 0 || minimumProbability > 100) {
      throw RangeError.range(minimumProbability, 0, 100, 'minimumProbability');
    }
    final blocked = blockedMarkets.map(_normalizeMarket).toSet();
    final picks = <SmartBetSportsMarketPick>[];

    for (final entry in rankedMarkets(sportsProbabilities)) {
      if (entry.value < minimumProbability ||
          blocked.contains(_normalizeMarket(entry.key))) continue;
      final odd = quotedOdds[entry.key];
      if (odd == null || !odd.isFinite || odd <= minimumOdd) continue;
      picks.add(
        SmartBetSportsMarketPick(
          market: entry.key,
          probability: entry.value,
          odd: odd,
        ),
      );
    }
    return List.unmodifiable(picks);
  }

  /// Compatibilita': la prima scelta resta identica al comportamento P20.
  static SmartBetSportsMarketPick? bestPlayable({
    required Map<String, int> sportsProbabilities,
    required Map<String, double> quotedOdds,
    Iterable<String> blockedMarkets = const <String>[],
    int minimumProbability = 0,
  }) {
    final picks = allPlayable(
      sportsProbabilities: sportsProbabilities,
      quotedOdds: quotedOdds,
      blockedMarkets: blockedMarkets,
      minimumProbability: minimumProbability,
    );
    return picks.isEmpty ? null : picks.first;
  }
}
