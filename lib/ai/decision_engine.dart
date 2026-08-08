import '../models/analysis_result.dart';
import '../models/match_comparison.dart';

class DecisionEngine {
  static AnalysisResult analyze(MatchComparison comparison) {
    final smartScore = 50 + comparison.difference;

    return AnalysisResult(
      smartScore: smartScore,
      homeProbability: comparison.favorite == "Equilibrio" ? 33 : 50,
      drawProbability: 25,
      awayProbability: comparison.favorite == "Equilibrio" ? 33 : 25,
      prediction: comparison.favorite,
      risk: comparison.difference >= 10 ? "Basso" : "Medio",
      valueBet: comparison.favorite,
      explanation:
          "${comparison.favorite} risulta favorita in base al confronto tra le due squadre.",
    );
  }
}
