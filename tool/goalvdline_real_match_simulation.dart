// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/ai/goalvdline_match_input_adapter.dart';
import '../lib/models/goalvdline_match_engine_models.dart';
import '../lib/models/match_model.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/match_dossier_builder.dart';

Future<void> main() async {
  const targetFixtureId = 1569956;

  final now = DateTime.now();
  final tomorrow = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));

  print('');
  print('============================================================');
  print('GOALVDLINE - TEST PARTITA REALE');
  print('Fixture target: $targetFixtureId');
  print('============================================================');

  final matches = await MatchRepository.getMatchesByDate(tomorrow);

  MatchModel? selected;

  for (final match in matches) {
    if (match.fixtureId == targetFixtureId) {
      selected = match;
      break;
    }
  }

  if (selected == null) {
    print('Fixture $targetFixtureId non trovata.');
    return;
  }

  final match = selected;

  print('');
  print('PARTITA TROVATA');
  print('${match.homeTeam} - ${match.awayTeam}');
  print('Competizione: ${match.league}');
  print('Paese: ${match.country}');
  print('Data: ${match.date}');
  print('AI weight: ${match.aiWeight}');
  print('Home ID: ${match.homeTeamId}');
  print('Away ID: ${match.awayTeamId}');

  final dossierBuilder = MatchDossierBuilder();

  try {
    print('');
    print('============================================================');
    print('COSTRUZIONE DOSSIER REALE');
    print('============================================================');

    final dossier = await dossierBuilder.build(match);

    if (dossier == null) {
      print('');
      print('ERRORE: dossier non costruito.');
      return;
    }

    print('');
    print('============================================================');
    print('DOSSIER COSTRUITO');
    print('============================================================');
    print('Data confidence: ${dossier.dataConfidence}/100');
    print('Forma casa: ${dossier.homeForm['count'] ?? 0}');
    print('Forma ospite: ${dossier.awayForm['count'] ?? 0}');
    print('H2H: ${dossier.headToHead.length}');
    print('Assenze: ${dossier.injuries.length}');
    print('Formazioni: ${dossier.probableLineups.length}');

    final input = GoalVdLineMatchInputAdapter.fromDossier(
      match: match,
      dossier: dossier,
      simulations: 20000,
    );

    print('');
    print('============================================================');
    print('STATO SQUADRE PASSATO AL NUOVO MOTORE');
    print('============================================================');

    _printTeamState('CASA', input.home);
    _printTeamState('OSPITE', input.away);

    print('');
    print('============================================================');
    print('ESECUZIONE 20.000 SIMULAZIONI');
    print('============================================================');

    final result = GoalVdLineMatchEngine.simulate(input);

    print('');
    print('============================================================');
    print('RISULTATO GOALVDLINE MATCH ENGINE');
    print('${match.homeTeam} - ${match.awayTeam}');
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
    print(
      'Under 1.5: '
      '${(result.under15Probability * 100).toStringAsFixed(1)}%',
    );

    print('Over 2.5: ${result.over25Percent.toStringAsFixed(1)}%');
    print(
      'Under 2.5: '
      '${(result.under25Probability * 100).toStringAsFixed(1)}%',
    );

    print('Over 3.5: ${result.over35Percent.toStringAsFixed(1)}%');
    print(
      'Under 3.5: '
      '${(result.under35Probability * 100).toStringAsFixed(1)}%',
    );

    print('Goal: ${result.goalPercent.toStringAsFixed(1)}%');
    print(
      'No Goal: '
      '${(result.noGoalProbability * 100).toStringAsFixed(1)}%',
    );

    print('');
    print('Qualità dati: ${result.dataConfidence}/100');
    print(
      'Affidabilità previsione: '
      '${result.predictionConfidence}/100',
    );

    print('');
    print('RISULTATI ESATTI PIÙ FREQUENTI');

    for (final score in result.exactScores) {
      print(
        '${score.label}: '
        '${score.probabilityPercent.toStringAsFixed(1)}%',
      );
    }

    if (result.warnings.isNotEmpty) {
      print('');
      print('AVVISI');

      for (final warning in result.warnings) {
        print('- $warning');
      }
    }

    print('');
    print('============================================================');
  } finally {
    dossierBuilder.dispose();
  }
}

void _printTeamState(String label, GoalVdLineTeamState team) {
  print('');
  print('--- $label: ${team.teamName} ---');

  print(
    'Forza strutturale: '
    '${team.structuralStrength.toStringAsFixed(1)}',
  );

  print(
    'Attacco: '
    '${team.attackStrength.toStringAsFixed(1)}',
  );

  print(
    'Difesa: '
    '${team.defenseStrength.toStringAsFixed(1)}',
  );

  print(
    'Forma recente: '
    '${team.recentFormStrength.toStringAsFixed(1)}',
  );

  print(
    'Casa/trasferta: '
    '${team.venueStrength.toStringAsFixed(1)}',
  );

  print(
    'Disponibilità: '
    '${team.availabilityStrength.toStringAsFixed(1)}',
  );

  print(
    'Gol medi: '
    '${team.goalsForPerMatch.toStringAsFixed(2)} fatti / '
    '${team.goalsAgainstPerMatch.toStringAsFixed(2)} subiti',
  );

  print(
    'Gol recenti: '
    '${team.recentGoalsForPerMatch.toStringAsFixed(2)} fatti / '
    '${team.recentGoalsAgainstPerMatch.toStringAsFixed(2)} subiti',
  );

  print(
    'Indisponibili: '
    '${team.unavailablePlayers}',
  );

  print(
    'Formazione disponibile: '
    '${team.lineupAvailable ? "SI" : "NO"}',
  );

  print(
    'Data confidence: '
    '${team.dataConfidence}/100',
  );
}
