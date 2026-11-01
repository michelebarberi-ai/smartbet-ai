import 'dart:math' as math;

import '../models/analysis_result.dart';
import 'smartbet_asian_handicap_settlement_service.dart';

/// P19H: solo mercati con probabilità di vittoria ben definita.
/// DNB: probabilità di vincita INCONDIZIONATA (il pareggio è rimborsato).
/// Asiatici: per ora solo linee a mezzo gol, senza esiti parziali.
class SmartBetRefundableMarketCandidateService {
  const SmartBetRefundableMarketCandidateService._();

  static const List<String> drawNoBet = ['DNB CASA', 'DNB OSPITE'];

  static int drawNoBetProbability(AnalysisResult result, String market) {
    return switch (market) {
      'DNB CASA' => result.homeProbability.clamp(0, 100),
      'DNB OSPITE' => result.awayProbability.clamp(0, 100),
      _ => 0,
    };
  }

  static int searchProxy(AnalysisResult result) =>
      math.max(result.homeProbability, result.awayProbability);

  static List<({String market, int probability})> asianCandidates({
    required AnalysisResult analysis,
    required Iterable<String> quotedOutcomes,
  }) {
    final homeLambda = analysis.expectedHomeGoals;
    final awayLambda = analysis.expectedAwayGoals;
    if (!homeLambda.isFinite ||
        !awayLambda.isFinite ||
        homeLambda <= 0 ||
        awayLambda <= 0 ||
        homeLambda > 6 ||
        awayLambda > 6) {
      return [];
    }

    final canonical = RegExp(r'^HCP ASIA (CASA|OSPITE) ([+-]?[012]\.5)$');
    final result = <({String market, int probability})>[];
    final seen = <String>{};
    for (final raw in quotedOutcomes) {
      final market = raw.trim().toUpperCase();
      final match = canonical.firstMatch(market);
      if (match == null || !seen.add(market)) continue;
      final line = double.tryParse(match.group(2)!);
      if (line == null) continue;
      final side = match.group(1) == 'CASA'
          ? SmartBetAsianSide.home
          : SmartBetAsianSide.away;

      var mass = 0.0;
      var winMass = 0.0;
      for (var home = 0; home <= 12; home++) {
        final pHome = _poisson(homeLambda, home);
        for (var away = 0; away <= 12; away++) {
          final p = pHome * _poisson(awayLambda, away);
          mass += p;
          final outcome = SmartBetAsianHandicapSettlementService.evaluate(
            homeGoals: home,
            awayGoals: away,
            side: side,
            handicap: line,
          );
          if (outcome == SmartBetAsianSettlement.win) winMass += p;
        }
      }
      if (mass <= 0) continue;
      final probability = ((winMass / mass) * 100).round().clamp(0, 100);
      if (probability > 0) {
        result.add((market: market, probability: probability));
      }
    }
    result.sort((a, b) => a.market.compareTo(b.market));
    return result;
  }

  static double _poisson(double lambda, int goals) {
    var factorial = 1.0;
    for (var i = 2; i <= goals; i++) {
      factorial *= i;
    }
    return math.pow(lambda, goals).toDouble() * math.exp(-lambda) / factorial;
  }
}
