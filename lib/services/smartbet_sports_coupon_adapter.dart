import '../models/analysis_result.dart';
import 'odds_service.dart';
import 'smartbet_european_handicap_candidate_service.dart';
import 'smartbet_sports_market_selector.dart';

class SmartBetSportsCouponAdapter {
  const SmartBetSportsCouponAdapter._();

  static SmartBetSportsMarketPick? bestPlayable({
    required AnalysisResult analysis,
    required FixtureMarketOdds? odds,
  }) {
    if (odds == null) return null;

    final probabilities = <String, int>{
      '1': analysis.homeProbability,
      'X': analysis.drawProbability,
      '2': analysis.awayProbability,
      'OVER 1.5': analysis.over15Probability,
      'UNDER 1.5': analysis.under15Probability,
      'OVER 2.5': analysis.over25Probability,
      'UNDER 2.5': analysis.under25Probability,
      'GOAL': analysis.goalProbability,
      'NO GOAL': analysis.noGoalProbability,
    };

    final home = analysis.expectedHomeGoals;
    final away = analysis.expectedAwayGoals;

    if (home.isFinite &&
        away.isFinite &&
        home >= 0 &&
        away >= 0 &&
        home <= 12 &&
        away <= 12) {
      for (final candidate
          in SmartBetEuropeanHandicapCandidateService.candidates(
            expectedHomeGoals: home,
            expectedAwayGoals: away,
            quotedOutcomes: odds.bestByOutcome.keys,
          )) {
        probabilities[candidate.market] = candidate.probability;
      }
    }

    return SmartBetSportsMarketSelector.bestPlayable(
      sportsProbabilities: probabilities,
      blockedMarkets: analysis.sportsAuditBlockedMarkets,
      quotedOdds: {
        for (final entry in odds.bestByOutcome.entries)
          entry.key: entry.value.odd,
      },
    );
  }
}
