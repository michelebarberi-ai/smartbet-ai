import '../models/team_analysis.dart';
import '../models/match_comparison.dart';

class MatchAnalyzer {
  static MatchComparison analyze({
    required TeamAnalysis homeTeam,
    required TeamAnalysis awayTeam,
  }) {
    final difference = homeTeam.teamScore - awayTeam.teamScore;

    String favorite;

    if (difference > 0) {
      favorite = homeTeam.teamName;
    } else if (difference < 0) {
      favorite = awayTeam.teamName;
    } else {
      favorite = "Equilibrio";
    }

    return MatchComparison(
      homeScore: homeTeam.teamScore,
      awayScore: awayTeam.teamScore,
      difference: difference.abs(),
      favorite: favorite,
    );
  }
}
