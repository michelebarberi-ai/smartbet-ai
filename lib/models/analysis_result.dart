class AnalysisResult {
  final int smartScore;

  final int homeProbability;
  final int drawProbability;
  final int awayProbability;

  final String prediction;
  final String risk;

  final String valueBet;

  final String explanation;

  const AnalysisResult({
    required this.smartScore,
    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,
    required this.prediction,
    required this.risk,
    required this.valueBet,
    required this.explanation,
  });
}
