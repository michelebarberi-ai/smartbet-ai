class AnalysisResult {
  final int smartScore;

  final int homeProbability;
  final int drawProbability;
  final int awayProbability;

  final String prediction;
  final String valueBet;
  final String risk;
  final String explanation;

  const AnalysisResult({
    required this.smartScore,
    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,
    required this.prediction,
    required this.valueBet,
    required this.risk,
    required this.explanation,
  });
}
