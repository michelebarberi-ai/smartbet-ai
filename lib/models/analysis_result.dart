class AnalysisResult {
  final int smartScore;

  // ============================================================
  // PROBABILITÀ 1X2
  // ============================================================

  final int homeProbability;
  final int drawProbability;
  final int awayProbability;

  // ============================================================
  // PROBABILITÀ MERCATI GOL
  // ============================================================

  final int over15Probability;
  final int under15Probability;

  final int over25Probability;
  final int under25Probability;

  final int goalProbability;
  final int noGoalProbability;

  // ============================================================
  // EXPECTED GOALS
  // ============================================================

  final double expectedHomeGoals;
  final double expectedAwayGoals;

  // ============================================================
  // PRONOSTICO / VALUE / RISCHIO
  // ============================================================

  final String prediction;

  final String valueBet;

  final String risk;

  // ============================================================
  // STAKE ENGINE
  // ============================================================

  final bool shouldBet;

  final double recommendedStakePercent;

  final double recommendedStakeUnits;

  final String stakeOutcome;

  final double stakeOdd;

  final String stakeBookmaker;

  final String stakeRecommendation;

  // ============================================================
  // BANKROLL
  // ============================================================

  final double recommendedStakeAmount;

  // ============================================================
  // SPIEGAZIONE
  // ============================================================

  final String explanation;

  const AnalysisResult({
    required this.smartScore,

    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,

    this.over15Probability = 0,
    this.under15Probability = 0,

    this.over25Probability = 0,
    this.under25Probability = 0,

    this.goalProbability = 0,
    this.noGoalProbability = 0,

    this.expectedHomeGoals = 0.0,
    this.expectedAwayGoals = 0.0,

    required this.prediction,
    required this.valueBet,
    required this.risk,

    this.shouldBet = false,
    this.recommendedStakePercent = 0.0,
    this.recommendedStakeUnits = 0.0,
    this.stakeOutcome = '',
    this.stakeOdd = 0.0,
    this.stakeBookmaker = '',
    this.stakeRecommendation = 'Nessuna puntata.',

    this.recommendedStakeAmount = 0.0,

    required this.explanation,
  });

  // ============================================================
  // BANKROLL
  // ============================================================

  double stakeAmountForBankroll(double bankroll) {
    if (!shouldBet || bankroll <= 0.0 || recommendedStakePercent <= 0.0) {
      return 0.0;
    }

    return bankroll * (recommendedStakePercent / 100.0);
  }

  // ============================================================
  // MIGLIORE PROBABILITÀ MERCATO GOL
  // ============================================================

  int get bestGoalMarketProbability {
    final values = <int>[
      over15Probability,
      under15Probability,
      over25Probability,
      under25Probability,
      goalProbability,
      noGoalProbability,
    ];

    return values.reduce((a, b) => a > b ? a : b);
  }

  // ============================================================
  // MIGLIORE MERCATO GOL
  // ============================================================

  String get bestGoalMarket {
    final values = <String, int>{
      'OVER 1.5': over15Probability,
      'UNDER 1.5': under15Probability,
      'OVER 2.5': over25Probability,
      'UNDER 2.5': under25Probability,
      'GOAL': goalProbability,
      'NO GOAL': noGoalProbability,
    };

    String bestMarket = '';
    int bestProbability = 0;

    for (final entry in values.entries) {
      if (entry.value > bestProbability) {
        bestProbability = entry.value;
        bestMarket = entry.key;
      }
    }

    return bestMarket;
  }
}
