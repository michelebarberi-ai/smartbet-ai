import 'smartbet_european_handicap_service.dart';

/// Costruisce candidati Handicap europeo soltanto
/// per gli esiti realmente presenti nel feed quote.
class SmartBetEuropeanHandicapCandidateService {
  const SmartBetEuropeanHandicapCandidateService._();

  static List<({String market, int probability})> candidates({
    required double expectedHomeGoals,
    required double expectedAwayGoals,
    required Iterable<String> quotedOutcomes,
  }) {
    if (!expectedHomeGoals.isFinite ||
        !expectedAwayGoals.isFinite ||
        expectedHomeGoals <= 0 ||
        expectedAwayGoals <= 0 ||
        expectedHomeGoals > 12 ||
        expectedAwayGoals > 12) {
      return [];
    }

    final pattern = RegExp(r'^HCP EURO CASA ([+-]?[0-9]+) ([1X2])$');

    final cache = <int, SmartBetEuropeanHandicapProbabilities>{};
    final results = <({String market, int probability})>[];
    final seen = <String>{};

    for (final raw in quotedOutcomes) {
      final market = raw.trim().toUpperCase();
      final match = pattern.firstMatch(market);

      if (match == null || !seen.add(market)) {
        continue;
      }

      final handicap = int.tryParse(match.group(1)!);

      if (handicap == null || handicap < -5 || handicap > 5) {
        continue;
      }

      final calculated = cache.putIfAbsent(
        handicap,
        () => SmartBetEuropeanHandicapService.evaluate(
          expectedHomeGoals: expectedHomeGoals,
          expectedAwayGoals: expectedAwayGoals,
          homeHandicap: handicap,
        ),
      );

      final probability = (calculated.forOutcome(match.group(2)!) * 100)
          .round()
          .clamp(0, 100);

      if (probability <= 0) {
        continue;
      }

      results.add((market: market, probability: probability));
    }

    results.sort((a, b) => a.market.compareTo(b.market));
    return results;
  }
}
