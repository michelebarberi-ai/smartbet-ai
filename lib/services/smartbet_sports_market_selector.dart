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

class SmartBetSportsMarketSelector {
  const SmartBetSportsMarketSelector._();

  static const double minimumOdd = 1.25;

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
      if (odd == null || !odd.isFinite || odd < minimumOdd) continue;
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
