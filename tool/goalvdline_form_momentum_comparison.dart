// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/ai/goalvdline_match_input_adapter.dart';
import '../lib/models/goalvdline_match_engine_models.dart';
import '../lib/models/match_model.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/match_dossier_builder.dart';

Future<void> main() async {
  const fixtureId = 1557412;

  final date = DateTime(2026, 9, 20);

  print('');
  print('============================================================');
  print('GOALVDLINE - FORM MOMENTUM COMPARISON');
  print('============================================================');

  final matches = await MatchRepository.getMatchesByDate(date);

  MatchModel? selected;

  for (final match in matches) {
    if (match.fixtureId == fixtureId) {
      selected = match;
      break;
    }
  }

  if (selected == null) {
    print('Fixture $fixtureId non trovata.');
    return;
  }

  final match = selected;

  print('');
  print('${match.homeTeam} - ${match.awayTeam}');
  print(match.league);
  print(match.date);

  final builder = MatchDossierBuilder();

  try {
    final dossier = await builder.build(match);

    if (dossier == null) {
      print('Dossier non disponibile.');
      return;
    }

    // ==========================================================
    // VERSIONE NUOVA - FORM MOMENTUM
    // ==========================================================

    final momentumInput = GoalVdLineMatchInputAdapter.fromDossier(
      match: match,
      dossier: dossier,
      simulations: 20000,
    );

    // ==========================================================
    // VERSIONE BASELINE - PESO UGUALE
    // ==========================================================

    final baselineHome = _buildBaselineTeam(
      team: momentumInput.home,
      form: dossier.homeForm,
    );

    final baselineAway = _buildBaselineTeam(
      team: momentumInput.away,
      form: dossier.awayForm,
    );

    final baselineInput = GoalVdLineMatchEngineInput(
      fixtureId: momentumInput.fixtureId,
      home: baselineHome,
      away: baselineAway,
      competitionWeight: momentumInput.competitionWeight,
      simulations: momentumInput.simulations,
    );

    final baselineResult = GoalVdLineMatchEngine.simulate(baselineInput);

    final momentumResult = GoalVdLineMatchEngine.simulate(momentumInput);

    // ==========================================================
    // DATI FORMA
    // ==========================================================

    print('');
    print('============================================================');
    print('FORMA RECENTE');
    print('============================================================');

    _printTeamComparison(
      teamName: match.homeTeam,
      baseline: baselineHome,
      momentum: momentumInput.home,
    );

    _printTeamComparison(
      teamName: match.awayTeam,
      baseline: baselineAway,
      momentum: momentumInput.away,
    );

    // ==========================================================
    // RISULTATI
    // ==========================================================

    print('');
    print('============================================================');
    print('SENZA FORM MOMENTUM');
    print('============================================================');

    _printResult(baselineResult);

    print('');
    print('============================================================');
    print('CON FORM MOMENTUM');
    print('============================================================');

    _printResult(momentumResult);

    // ==========================================================
    // DIFFERENZE
    // ==========================================================

    print('');
    print('============================================================');
    print('EFFETTO DEL FORM MOMENTUM');
    print('============================================================');

    print(
      'Expected Goals casa: '
      '${_signed(momentumResult.expectedHomeGoals - baselineResult.expectedHomeGoals)}',
    );

    print(
      'Expected Goals ospite: '
      '${_signed(momentumResult.expectedAwayGoals - baselineResult.expectedAwayGoals)}',
    );

    print(
      '1: '
      '${_signed(momentumResult.homeWinPercent - baselineResult.homeWinPercent)} punti',
    );

    print(
      'X: '
      '${_signed(momentumResult.drawPercent - baselineResult.drawPercent)} punti',
    );

    print(
      '2: '
      '${_signed(momentumResult.awayWinPercent - baselineResult.awayWinPercent)} punti',
    );

    print(
      'Over 2.5: '
      '${_signed(momentumResult.over25Percent - baselineResult.over25Percent)} punti',
    );

    print(
      'Goal: '
      '${_signed(momentumResult.goalPercent - baselineResult.goalPercent)} punti',
    );

    print('');
    print('============================================================');
  } finally {
    builder.dispose();
  }
}

GoalVdLineTeamState _buildBaselineTeam({
  required GoalVdLineTeamState team,
  required Map<String, dynamic> form,
}) {
  final snapshot = _parseUnweightedRecent(teamName: team.teamName, form: form);

  if (snapshot.matches <= 0) {
    return team;
  }

  final recentFormStrength =
      (((snapshot.wins * 3 + snapshot.draws) / (snapshot.matches * 3)) * 100.0)
          .clamp(0.0, 100.0)
          .toDouble();

  final recentGoalsFor = snapshot.goalsFor / snapshot.matches;

  final recentGoalsAgainst = snapshot.goalsAgainst / snapshot.matches;

  return GoalVdLineTeamState(
    teamId: team.teamId,
    teamName: team.teamName,
    structuralStrength: team.structuralStrength,
    squadStrength: team.squadStrength,
    attackStrength: team.attackStrength,
    defenseStrength: team.defenseStrength,
    recentFormStrength: recentFormStrength,
    venueStrength: team.venueStrength,
    motivationStrength: team.motivationStrength,
    availabilityStrength: team.availabilityStrength,
    goalsForPerMatch: team.goalsForPerMatch,
    goalsAgainstPerMatch: team.goalsAgainstPerMatch,
    recentGoalsForPerMatch: recentGoalsFor,
    recentGoalsAgainstPerMatch: recentGoalsAgainst,
    injuredPlayers: team.injuredPlayers,
    suspendedPlayers: team.suspendedPlayers,
    unavailablePlayers: team.unavailablePlayers,
    contextAdjustment: team.contextAdjustment,
    lineupAvailable: team.lineupAvailable,
    dataConfidence: team.dataConfidence,
    contextNotes: team.contextNotes,
  );
}

_UnweightedSnapshot _parseUnweightedRecent({
  required String teamName,
  required Map<String, dynamic> form,
}) {
  final rawMatches = form['matches'];

  if (rawMatches is! List) {
    return const _UnweightedSnapshot();
  }

  final normalizedTeam = teamName.trim().toLowerCase();

  final scorePattern = RegExp(r'(\d+)\s*-\s*(\d+)');

  var matches = 0;
  var wins = 0;
  var draws = 0;
  var goalsFor = 0;
  var goalsAgainst = 0;

  for (final raw in rawMatches) {
    final text = raw.toString().trim();

    final score = scorePattern.firstMatch(text);

    if (score == null) {
      continue;
    }

    final homeGoals = int.tryParse(score.group(1) ?? '');

    final awayGoals = int.tryParse(score.group(2) ?? '');

    if (homeGoals == null || awayGoals == null) {
      continue;
    }

    final beforeScore = text.substring(0, score.start).trim().toLowerCase();

    final afterScore = text.substring(score.end).trim().toLowerCase();

    final int teamGoals;
    final int opponentGoals;

    if (beforeScore.contains(normalizedTeam)) {
      teamGoals = homeGoals;
      opponentGoals = awayGoals;
    } else if (afterScore.contains(normalizedTeam)) {
      teamGoals = awayGoals;
      opponentGoals = homeGoals;
    } else {
      continue;
    }

    matches++;
    goalsFor += teamGoals;
    goalsAgainst += opponentGoals;

    if (teamGoals > opponentGoals) {
      wins++;
    } else if (teamGoals == opponentGoals) {
      draws++;
    }
  }

  return _UnweightedSnapshot(
    matches: matches,
    wins: wins,
    draws: draws,
    goalsFor: goalsFor,
    goalsAgainst: goalsAgainst,
  );
}

void _printTeamComparison({
  required String teamName,
  required GoalVdLineTeamState baseline,
  required GoalVdLineTeamState momentum,
}) {
  print('');
  print(teamName);

  print(
    'Forma senza momentum: '
    '${baseline.recentFormStrength.toStringAsFixed(1)}',
  );

  print(
    'Forma con momentum:   '
    '${momentum.recentFormStrength.toStringAsFixed(1)}',
  );

  print(
    'Gol recenti senza momentum: '
    '${baseline.recentGoalsForPerMatch.toStringAsFixed(2)} / '
    '${baseline.recentGoalsAgainstPerMatch.toStringAsFixed(2)}',
  );

  print(
    'Gol recenti con momentum:   '
    '${momentum.recentGoalsForPerMatch.toStringAsFixed(2)} / '
    '${momentum.recentGoalsAgainstPerMatch.toStringAsFixed(2)}',
  );
}

void _printResult(GoalVdLineMatchEngineResult result) {
  print(
    'xG: '
    '${result.expectedHomeGoals.toStringAsFixed(2)} - '
    '${result.expectedAwayGoals.toStringAsFixed(2)}',
  );

  print('1: ${result.homeWinPercent.toStringAsFixed(1)}%');

  print('X: ${result.drawPercent.toStringAsFixed(1)}%');

  print('2: ${result.awayWinPercent.toStringAsFixed(1)}%');

  print(
    'Over 2.5: '
    '${result.over25Percent.toStringAsFixed(1)}%',
  );

  print(
    'Goal: '
    '${result.goalPercent.toStringAsFixed(1)}%',
  );

  print(
    'Affidabilità: '
    '${result.predictionConfidence}/100',
  );
}

String _signed(double value) {
  final prefix = value >= 0 ? '+' : '';

  return '$prefix${value.toStringAsFixed(2)}';
}

class _UnweightedSnapshot {
  final int matches;
  final int wins;
  final int draws;
  final int goalsFor;
  final int goalsAgainst;

  const _UnweightedSnapshot({
    this.matches = 0,
    this.wins = 0,
    this.draws = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
  });
}
