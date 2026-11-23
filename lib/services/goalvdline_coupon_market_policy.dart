import '../models/analysis_result.dart';
import 'smartbet_european_handicap_candidate_service.dart';
import 'smartbet_refundable_market_candidate_service.dart';

/// B78: boundary between simple, playable Coupon markets and the complete
/// sporting analysis visible in the match details / Combinazioni AI.
/// No bookmaker price participates in this boundary or in the ranking.
class GoalVdLineCouponMarketPolicy {
  const GoalVdLineCouponMarketPolicy._();

  static const List<String> coreMarketOrder = [
    '1', 'X', '2',
    '1X', 'X2', '12',
    'OVER 1.5', 'UNDER 1.5',
    'OVER 2.5', 'UNDER 2.5',
    'OVER 3.5', 'UNDER 3.5',
    'OVER 4.5', 'UNDER 4.5',
    'MULTIGOL 1-4', 'MULTIGOL 2-4',
    'MULTIGOL 2-5', 'MULTIGOL 3-5',
    'GOAL', 'NO GOAL',
  ];

  // Conservative half/integer handicap lines for Crea Schedina.
  // Wide +/-3, exotic quarter, complex combos and other special markets
  // remain reviewable in Combinazioni AI; they never enter coupon picks.
  static const List<String> _europeanLines = [
    'HCP EURO CASA -1 1', 'HCP EURO CASA -1 X',
    'HCP EURO CASA -1 2',
    'HCP EURO CASA 1 1', 'HCP EURO CASA 1 X',
    'HCP EURO CASA 1 2',
  ];
  static const List<String> _asianLines = [
    'HCP ASIA CASA -1.5', 'HCP ASIA CASA -0.5',
    'HCP ASIA CASA 0.5', 'HCP ASIA CASA 1.5',
    'HCP ASIA OSPITE -1.5', 'HCP ASIA OSPITE -0.5',
    'HCP ASIA OSPITE 0.5', 'HCP ASIA OSPITE 1.5',
  ];

  // Crea Schedina B79: ONLY European Handicap is selectable.
  // Asian lines remain available in Combinazioni AI and the full analysis.
  static const List<String> couponHandicapMarkets = _europeanLines;

  static bool isAllowedCouponMarket(String market) {
    final normalized = market.trim().toUpperCase();
    return coreMarketOrder.contains(normalized) ||
        couponHandicapMarkets.contains(normalized);
  }

  /// Only presentation metadata: AFC Champions League is Asian even if
  /// an upstream fixture catalog incorrectly labels the region as Europe.
  /// Never changes the fixture identity, Italian filters or sports model.
  static String displayCountry(String country, String league) {
    if (league.trim().toUpperCase().contains('AFC CHAMPIONS LEAGUE')) {
      return 'Asia';
    }
    return country;
  }

  /// Candidate handicap probabilities are generated from a FIXED sporting
  /// catalogue, even when the bookmaker feed is missing. The canonical
  /// quotedOutcomes parameter is only a market-ID whitelist here; no
  /// bookmaker prices or offered lines are read or used by the model.
  static List<({String market, int probability})> sportingHandicaps(
    AnalysisResult analysis,
  ) {
    final european = SmartBetEuropeanHandicapCandidateService.candidates(
      expectedHomeGoals: analysis.expectedHomeGoals,
      expectedAwayGoals: analysis.expectedAwayGoals,
      quotedOutcomes: _europeanLines,
    );
    return european;
  }

  /// Complete information panel: includes Asian handicap as well, but
  /// does not alter the restricted coupon selection or its price filter.
  static List<({String market, int probability})> analysisHandicaps(
    AnalysisResult analysis,
  ) {
    final asian = SmartBetRefundableMarketCandidateService.asianCandidates(
      analysis: analysis,
      quotedOutcomes: _asianLines,
    );
    return [
      ...sportingHandicaps(analysis),
      ...asian,
    ];
  }
}
