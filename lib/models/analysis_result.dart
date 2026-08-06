class AnalysisResult {
  final int smartScore;

  final int homeProbability;
  final int drawProbability;
  final int awayProbability;

  final String valueBet;
  final double odd;

  final String risk;

  final String explanation;

  const AnalysisResult({
    required this.smartScore,
    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,
    required this.valueBet,
    required this.odd,
    required this.risk,
    required this.explanation,
  });
}
