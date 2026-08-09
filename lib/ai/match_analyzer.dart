import '../models/team_analysis.dart';
import '../models/match_comparison.dart';

class MatchAnalyzer {
  static MatchComparison analyze({
    required TeamAnalysis homeTeam,
    required TeamAnalysis awayTeam,
  }) {
    final difference = homeTeam.totalScore - awayTeam.totalScore;

    String favorite;

    if (difference > 0) {
      favorite = homeTeam.teamName;
    } else if (difference < 0) {
      favorite = awayTeam.teamName;
    } else {
      favorite = "Equilibrio";
    }

    return MatchComparison(
      homeScore: homeTeam.totalScore.round(),
      awayScore: awayTeam.totalScore.round(),
      difference: difference.abs().round(),
      favorite: favorite,
    );
  }
}
