// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/ai/goalvdline_match_input_adapter.dart';
import '../lib/ai/smartcore.dart';
import '../lib/models/match_model.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/match_dossier_builder.dart';

Future<void> main() async {
  const fixtureId = 1569956;

  final now = DateTime.now();

  final date = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));

  print('');
  print('============================================================');
  print('GOALVDLINE - CONFRONTO VECCHIO vs NUOVO MOTORE');
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
  print('${match.league} - ${match.date}');

  // ============================================================
  // VECCHIO MOTORE
  // ============================================================

  print('');
  print('============================================================');
  print('VECCHIO SMARTCORE');
  print('============================================================');

  final oldResult = await SmartCore.analyze(match);

  print('Smart Score: ${oldResult.smartScore}');

  print('1: ${oldResult.homeProbability}%');

  print('X: ${oldResult.drawProbability}%');

  print('2: ${oldResult.awayProbability}%');

  print('Over 2.5: ${oldResult.over25Probability}%');

  print('Under 2.5: ${oldResult.under25Probability}%');

  print('Goal: ${oldResult.goalProbability}%');

  print('No Goal: ${oldResult.noGoalProbability}%');

  // ============================================================
  // NUOVO MOTORE
  // ============================================================

  print('');
  print('============================================================');
  print('NUOVO GOALVDLINE MATCH ENGINE');
  print('============================================================');

  final builder = MatchDossierBuilder();

  try {
    final dossier = await builder.build(match);

    if (dossier == null) {
      print('Impossibile costruire il dossier.');
      return;
    }

    final input = GoalVdLineMatchInputAdapter.fromDossier(
      match: match,
      dossier: dossier,
      simulations: 20000,
    );

    final newResult = GoalVdLineMatchEngine.simulate(input);

    print('1: ${newResult.homeWinPercent.toStringAsFixed(1)}%');

    print('X: ${newResult.drawPercent.toStringAsFixed(1)}%');

    print('2: ${newResult.awayWinPercent.toStringAsFixed(1)}%');

    print('Over 2.5: ${newResult.over25Percent.toStringAsFixed(1)}%');

    print(
      'Under 2.5: '
      '${(newResult.under25Probability * 100).toStringAsFixed(1)}%',
    );

    print('Goal: ${newResult.goalPercent.toStringAsFixed(1)}%');

    print(
      'No Goal: '
      '${(newResult.noGoalProbability * 100).toStringAsFixed(1)}%',
    );

    print('');
    print('Qualità dati: ${newResult.dataConfidence}/100');

    print('Affidabilità: ${newResult.predictionConfidence}/100');

    // ==========================================================
    // DIFFERENZE 1X2
    // ==========================================================

    print('');
    print('============================================================');
    print('DIFFERENZA NUOVO - VECCHIO');
    print('============================================================');

    final homeDifference = newResult.homeWinPercent - oldResult.homeProbability;

    final drawDifference = newResult.drawPercent - oldResult.drawProbability;

    final awayDifference = newResult.awayWinPercent - oldResult.awayProbability;

    print('1: ${_signed(homeDifference)} punti');

    print('X: ${_signed(drawDifference)} punti');

    print('2: ${_signed(awayDifference)} punti');

    print('');
    print('============================================================');
  } finally {
    builder.dispose();
  }
}

String _signed(double value) {
  final prefix = value >= 0 ? '+' : '';

  return '$prefix${value.toStringAsFixed(1)}';
}
