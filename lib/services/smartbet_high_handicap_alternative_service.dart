import '../models/analysis_result.dart';
import 'goalvdline_quote_policy.dart';
import 'odds_service.dart';
import 'smartbet_local_auditor.dart';
import 'smartbet_market_probability_service.dart';

/// An additional *quoted* option for an unusually wide handicap.
/// The original AI forecast/coupon pick is never replaced automatically.
class SmartBetHighHandicapAlternative {
  final String market;
  final int probability;
  final double odd;
  final String bookmaker;
  final bool withReservation;

  const SmartBetHighHandicapAlternative({
    required this.market,
    required this.probability,
    required this.odd,
    required this.bookmaker,
    required this.withReservation,
  });
}

class SmartBetHighHandicapAlternativeService {
  const SmartBetHighHandicapAlternativeService._();

  static final _european =
      RegExp(r'^HCP EURO CASA ([+-]?\d+) [1X2]$');
  static final _asian =
      RegExp(r'^HCP ASIA (?:CASA|OSPITE) ([+-]?\d+(?:\.\d+)?)$');

  /// Large handicap: magnitude of at least 3 goals, on either side.
  /// Asian half/quarter goals are supported only for detecting the warning.
  static bool needsAlternative(String market) {
    final value = market.trim().toUpperCase();
    final match = _european.firstMatch(value) ?? _asian.firstMatch(value);
    if (match == null) return false;
    final handicap = double.tryParse(match.group(1)!);
    return handicap != null && handicap.isFinite && handicap.abs() >= 3;
  }

  // Common bookable full-time markets, not invented handicap lines or
  // unquoted OR/combination markets.
  static const _alternatives = <String>[
    '1X', 'X2', '12', '1', 'X', '2',
    'OVER 1.5', 'UNDER 1.5', 'OVER 2.5', 'UNDER 2.5',
    'UNDER 3.5', 'GOAL', 'NO GOAL', 'CASA SEGNA', 'OSPITE SEGNA',
  ];

  static int _probability(AnalysisResult analysis, String market) {
    switch (market) {
      case '1':
        return analysis.homeProbability;
      case 'X':
        return analysis.drawProbability;
      case '2':
        return analysis.awayProbability;
      case '1X':
        return (analysis.homeProbability + analysis.drawProbability)
            .clamp(0, 100);
      case 'X2':
        return (analysis.awayProbability + analysis.drawProbability)
            .clamp(0, 100);
      case '12':
        return (analysis.homeProbability + analysis.awayProbability)
            .clamp(0, 100);
      case 'OVER 1.5':
        return analysis.over15Probability;
      case 'UNDER 1.5':
        return analysis.under15Probability;
      case 'OVER 2.5':
        return analysis.over25Probability;
      case 'UNDER 2.5':
        return analysis.under25Probability;
      case 'GOAL':
        return analysis.goalProbability;
      case 'NO GOAL':
        return analysis.noGoalProbability;
      default:
        return SmartBetMarketProbabilityService.probabilityFor(analysis, market);
    }
  }

  /// Odds are used ONLY for availability after the independent sports ranking.
  /// If nothing passes real price, probability, and auditor gates, return null.
  static SmartBetHighHandicapAlternative? find({
    required String primaryMarket,
    required AnalysisResult analysis,
    required FixtureMarketOdds? odds,
    int minimumProbability = 65,
    double minimumOdd = GoalVdLineQuotePolicy.minimumOdd,
  }) {
    if (!needsAlternative(primaryMarket) || odds == null) return null;
    if (minimumProbability < 0 || minimumProbability > 100) {
      throw RangeError.range(
        minimumProbability, 0, 100, 'minimumProbability',
      );
    }
    final ranked = [
      for (final market in _alternatives)
        (market: market, probability: _probability(analysis, market)),
    ]..sort((a, b) {
      final order = b.probability.compareTo(a.probability);
      return order != 0 ? order : a.market.compareTo(b.market);
    });

    for (final candidate in ranked) {
      if (candidate.probability < minimumProbability) break;
      final quote = odds.oddFor(candidate.market);
      if (quote == null ||
          !quote.odd.isFinite ||
          quote.odd <= minimumOdd ||
          quote.bookmakerName.trim().isEmpty) {
        continue;
      }
      final audit = SmartBetLocalAuditor.evaluate(
        analysis: analysis,
        market: candidate.market,
        probability: candidate.probability,
        odd: quote.odd,
      );
      if (audit.isBlocked || audit.blocksMarket(candidate.market)) continue;
      return SmartBetHighHandicapAlternative(
        market: candidate.market,
        probability: candidate.probability,
        odd: quote.odd,
        bookmaker: quote.bookmakerName,
        withReservation: audit.isDoubt,
      );
    }
    return null;
  }
}
