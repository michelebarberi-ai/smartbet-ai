class GoalVdLineTeamState {
  final int teamId;
  final String teamName;

  final double structuralStrength;
  final double squadStrength;
  final double attackStrength;
  final double defenseStrength;

  final double recentFormStrength;
  final double venueStrength;
  final double motivationStrength;
  final double availabilityStrength;

  final double goalsForPerMatch;
  final double goalsAgainstPerMatch;
  final double recentGoalsForPerMatch;
  final double recentGoalsAgainstPerMatch;

  final int injuredPlayers;
  final int suspendedPlayers;
  final int unavailablePlayers;

  final double contextAdjustment;

  final bool lineupAvailable;

  final int dataConfidence;

  final List<String> contextNotes;

  const GoalVdLineTeamState({
    required this.teamId,
    required this.teamName,
    required this.structuralStrength,
    required this.squadStrength,
    required this.attackStrength,
    required this.defenseStrength,
    required this.recentFormStrength,
    required this.venueStrength,
    required this.motivationStrength,
    required this.availabilityStrength,
    required this.goalsForPerMatch,
    required this.goalsAgainstPerMatch,
    required this.recentGoalsForPerMatch,
    required this.recentGoalsAgainstPerMatch,
    required this.injuredPlayers,
    required this.suspendedPlayers,
    required this.unavailablePlayers,
    required this.contextAdjustment,
    required this.lineupAvailable,
    required this.dataConfidence,
    this.contextNotes = const [],
  });
}

class GoalVdLineMatchEngineInput {
  final int fixtureId;

  final GoalVdLineTeamState home;
  final GoalVdLineTeamState away;

  final double competitionWeight;

  final int simulations;

  const GoalVdLineMatchEngineInput({
    required this.fixtureId,
    required this.home,
    required this.away,
    required this.competitionWeight,
    this.simulations = 20000,
  });
}

class GoalVdLineExactScore {
  final int homeGoals;
  final int awayGoals;

  final double probability;

  const GoalVdLineExactScore({
    required this.homeGoals,
    required this.awayGoals,
    required this.probability,
  });

  double get probabilityPercent => probability * 100.0;

  String get label => '$homeGoals-$awayGoals';
}

class GoalVdLineMatchEngineResult {
  final double expectedHomeGoals;
  final double expectedAwayGoals;

  double get expectedTotalGoals => expectedHomeGoals + expectedAwayGoals;

  final double homeWinProbability;
  final double drawProbability;
  final double awayWinProbability;

  final double over15Probability;
  final double over25Probability;
  final double over35Probability;

  final double goalProbability;

  double get under15Probability => 1.0 - over15Probability;
  double get under25Probability => 1.0 - over25Probability;
  double get under35Probability => 1.0 - over35Probability;
  double get noGoalProbability => 1.0 - goalProbability;

  final int dataConfidence;
  final int predictionConfidence;

  final int simulations;

  final List<GoalVdLineExactScore> exactScores;

  final List<String> warnings;

  const GoalVdLineMatchEngineResult({
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
    required this.homeWinProbability,
    required this.drawProbability,
    required this.awayWinProbability,
    required this.over15Probability,
    required this.over25Probability,
    required this.over35Probability,
    required this.goalProbability,
    required this.dataConfidence,
    required this.predictionConfidence,
    required this.simulations,
    required this.exactScores,
    this.warnings = const [],
  });

  double get homeWinPercent => homeWinProbability * 100.0;
  double get drawPercent => drawProbability * 100.0;
  double get awayWinPercent => awayWinProbability * 100.0;

  double get over15Percent => over15Probability * 100.0;
  double get over25Percent => over25Probability * 100.0;
  double get over35Percent => over35Probability * 100.0;

  double get goalPercent => goalProbability * 100.0;
}
