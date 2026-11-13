import 'diego_ai_market_probability_service.dart';
import 'odds_service.dart';
import 'goalvdline_quote_policy.dart';

/// Selezione sportiva DiegoAI indipendente dal Value Engine.
class DiegoAiSportsMarketPick {
  final String market;

  /// Probabilita' sportiva originale, nell'intervallo 0..1.
  final double probability;

  final double odd;
  final String bookmaker;

  const DiegoAiSportsMarketPick({
    required this.market,
    required this.probability,
    required this.odd,
    required this.bookmaker,
  });
}

class DiegoAiSportsMarketSelector {
  const DiegoAiSportsMarketSelector._();

  static const double minimumOdd = GoalVdLineQuotePolicy.minimumOdd;

  static DiegoAiSportsMarketPick? bestPlayable({
    required Iterable<DiegoAiMarketProbability> markets,
    required FixtureMarketOdds? odds,
  }) {
    if (odds == null) return null;

    final ranked = markets
        .where(
          (market) =>
              market.market.trim().isNotEmpty &&
              market.probability.isFinite &&
              market.probability > 0.0 &&
              market.probability <= 1.0,
        )
        .toList();

    // La classifica dipende esclusivamente dalle probabilita'.
    ranked.sort((a, b) {
      final comparison = b.probability.compareTo(a.probability);

      if (comparison != 0) return comparison;

      return a.market.compareTo(b.market);
    });

    // Le quote servono soltanto a verificare se il
    // mercato e' effettivamente utilizzabile.
    for (final market in ranked) {
      final quoted = odds.oddFor(market.market);

      if (quoted == null || !quoted.odd.isFinite || quoted.odd < minimumOdd) {
        continue;
      }

      return DiegoAiSportsMarketPick(
        market: market.market,
        probability: market.probability,
        odd: quoted.odd,
        bookmaker: quoted.bookmakerName,
      );
    }

    return null;
  }
}
