import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/models/goalvdline_match_engine_models.dart';

void main() {
  _scenarioStrongHome();
  _scenarioBalanced();
  _scenarioStrongButBadMoment();
}

void _scenarioStrongHome() {
  final home = GoalVdLineTeamState(
    teamId: 1,
    teamName: 'Casa Forte',
    structuralStrength: 82,
    squadStrength: 84,
    attackStrength: 80,
    defenseStrength: 76,
    recentFormStrength: 85,
    venueStrength: 88,
    motivationStrength: 80,
    availabilityStrength: 92,
    goalsForPerMatch: 2.05,
    goalsAgainstPerMatch: 0.85,
    recentGoalsForPerMatch: 2.30,
    recentGoalsAgainstPerMatch: 0.70,
    injuredPlayers: 1,
    suspendedPlayers: 0,
    unavailablePlayers: 1,
    contextAdjustment: 0.03,
    lineupAvailable: true,
    dataConfidence: 90,
  );

  final away = GoalVdLineTeamState(
    teamId: 2,
    teamName: 'Ospite Media',
    structuralStrength: 61,
    squadStrength: 62,
    attackStrength: 58,
    defenseStrength: 60,
    recentFormStrength: 48,
    venueStrength: 44,
    motivationStrength: 55,
    availabilityStrength: 82,
    goalsForPerMatch: 1.10,
    goalsAgainstPerMatch: 1.55,
    recentGoalsForPerMatch: 0.90,
    recentGoalsAgainstPerMatch: 1.70,
    injuredPlayers: 2,
    suspendedPlayers: 0,
    unavailablePlayers: 2,
    contextAdjustment: 0,
    lineupAvailable: true,
    dataConfidence: 86,
  );

  _run(
    title: 'SCENARIO 1 - CASA FORTE E IN FORMA',
    fixtureId: 1001,
    home: home,
    away: away,
  );
}

void _scenarioBalanced() {
  final home = GoalVdLineTeamState(
    teamId: 3,
    teamName: 'Casa Equilibrata',
    structuralStrength: 68,
    squadStrength: 68,
    attackStrength: 65,
    defenseStrength: 67,
    recentFormStrength: 62,
    venueStrength: 67,
    motivationStrength: 65,
    availabilityStrength: 90,
    goalsForPerMatch: 1.35,
    goalsAgainstPerMatch: 1.15,
    recentGoalsForPerMatch: 1.30,
    recentGoalsAgainstPerMatch: 1.10,
    injuredPlayers: 0,
    suspendedPlayers: 0,
    unavailablePlayers: 0,
    contextAdjustment: 0,
    lineupAvailable: true,
    dataConfidence: 88,
  );

  final away = GoalVdLineTeamState(
    teamId: 4,
    teamName: 'Ospite Equilibrata',
    structuralStrength: 69,
    squadStrength: 70,
    attackStrength: 67,
    defenseStrength: 68,
    recentFormStrength: 65,
    venueStrength: 63,
    motivationStrength: 66,
    availabilityStrength: 90,
    goalsForPerMatch: 1.38,
    goalsAgainstPerMatch: 1.12,
    recentGoalsForPerMatch: 1.40,
    recentGoalsAgainstPerMatch: 1.05,
    injuredPlayers: 0,
    suspendedPlayers: 0,
    unavailablePlayers: 0,
    contextAdjustment: 0,
    lineupAvailable: true,
    dataConfidence: 88,
  );

  _run(
    title: 'SCENARIO 2 - PARTITA EQUILIBRATA',
    fixtureId: 1002,
    home: home,
    away: away,
  );
}

void _scenarioStrongButBadMoment() {
  final home = GoalVdLineTeamState(
    teamId: 5,
    teamName: 'Grande in Crisi',
    structuralStrength: 86,
    squadStrength: 88,
    attackStrength: 80,
    defenseStrength: 76,
    recentFormStrength: 28,
    venueStrength: 48,
    motivationStrength: 38,
    availabilityStrength: 58,
    goalsForPerMatch: 1.90,
    goalsAgainstPerMatch: 0.95,
    recentGoalsForPerMatch: 0.70,
    recentGoalsAgainstPerMatch: 1.65,
    injuredPlayers: 4,
    suspendedPlayers: 1,
    unavailablePlayers: 5,
    contextAdjustment: -0.10,
    lineupAvailable: false,
    dataConfidence: 72,
    contextNotes: const [
      'Momento recente negativo.',
      'Diverse assenze nella rosa.',
    ],
  );

  final away = GoalVdLineTeamState(
    teamId: 6,
    teamName: 'Piccola in Forma',
    structuralStrength: 62,
    squadStrength: 63,
    attackStrength: 66,
    defenseStrength: 61,
    recentFormStrength: 84,
    venueStrength: 68,
    motivationStrength: 82,
    availabilityStrength: 94,
    goalsForPerMatch: 1.25,
    goalsAgainstPerMatch: 1.30,
    recentGoalsForPerMatch: 1.85,
    recentGoalsAgainstPerMatch: 0.85,
    injuredPlayers: 0,
    suspendedPlayers: 0,
    unavailablePlayers: 0,
    contextAdjustment: 0.05,
    lineupAvailable: true,
    dataConfidence: 84,
  );

  _run(
    title: 'SCENARIO 3 - FORTE SULLA CARTA, MA IN CRISI',
    fixtureId: 1003,
    home: home,
    away: away,
  );
}

void _run({
  required String title,
  required int fixtureId,
  required GoalVdLineTeamState home,
  required GoalVdLineTeamState away,
}) {
  final result = GoalVdLineMatchEngine.simulate(
    GoalVdLineMatchEngineInput(
      fixtureId: fixtureId,
      home: home,
      away: away,
      competitionWeight: 0.90,
      simulations: 20000,
    ),
  );

  print('');
  print('============================================================');
  print(title);
  print('${home.teamName} - ${away.teamName}');
  print('============================================================');

  print(
    'Expected Goals: '
    '${result.expectedHomeGoals.toStringAsFixed(2)} - '
    '${result.expectedAwayGoals.toStringAsFixed(2)}',
  );

  print('');
  print('1: ${result.homeWinPercent.toStringAsFixed(1)}%');
  print('X: ${result.drawPercent.toStringAsFixed(1)}%');
  print('2: ${result.awayWinPercent.toStringAsFixed(1)}%');

  print('');
  print('Over 1.5: ${result.over15Percent.toStringAsFixed(1)}%');
  print('Over 2.5: ${result.over25Percent.toStringAsFixed(1)}%');
  print('Over 3.5: ${result.over35Percent.toStringAsFixed(1)}%');
  print('Goal: ${result.goalPercent.toStringAsFixed(1)}%');

  print('');
  print('Qualità dati: ${result.dataConfidence}/100');
  print('Affidabilità previsione: ${result.predictionConfidence}/100');

  print('');
  print('Risultati esatti più frequenti:');

  for (final score in result.exactScores) {
    print(
      '${score.label}: '
      '${score.probabilityPercent.toStringAsFixed(1)}%',
    );
  }

  if (result.warnings.isNotEmpty) {
    print('');
    print('Avvisi:');

    for (final warning in result.warnings) {
      print('- $warning');
    }
  }

  print('============================================================');
}
