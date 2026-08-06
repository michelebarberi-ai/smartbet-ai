import '../models/match_model.dart';

class ConfidenceEngine {
  static int calculate(MatchModel match) {
    int score = match.smartScore;

    // Manteniamo il valore tra 0 e 100
    if (score > 100) score = 100;
    if (score < 0) score = 0;

    return score;
  }
}
