// ignore_for_file: avoid_print, avoid_relative_lib_imports

import 'dart:math' as math;

import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/ai/goalvdline_match_input_adapter.dart';
import '../lib/models/goalvdline_match_engine_models.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/football_api_service.dart';
import '../lib/services/match_dossier_builder.dart';

Future<void> main() async {
  final date = DateTime(2026, 9, 20);

  print('');
  print('============================================================');
  print('GOALVDLINE - MINI BACKTEST FORM MOMENTUM');
  print('============================================================');

  final matches = await MatchRepository.getMatchesByDate(date);

  final rawFixtures = await FootballApiService().getMatchesByDate(date);

  final rawByFixture = <int, Map<String, dynamic>>{};

  for (final raw in rawFixtures) {
    if (raw is! Map<String, dynamic>) {
      continue;
    }

    final fixture = raw['fixture'];

    if (fixture is! Map<String, dynamic>) {
      continue;
    }

    final fixtureId = _toInt(fixture['id']);

    if (fixtureId > 0) {
      rawByFixture[fixtureId] = raw;
    }
  }

  final candidates =
      matches.where((match) {
        if (!match.hasTeamIds ||
            match.fixtureId <= 0 ||
            match.isFriendly ||
            match.aiWeight < 0.95) {
          return false;
        }

        final raw = rawByFixture[match.fixtureId];

        if (raw == null) {
          return false;
        }

        return _actualResult(raw) != null;
      }).toList()..sort((a, b) {
        final weight = b.aiWeight.compareTo(a.aiWeight);

        if (weight != 0) {
          return weight;
        }

        return a.fixtureId.compareTo(b.fixtureId);
      });

  final selected = candidates.take(3).toList();

  if (selected.isEmpty) {
    print('Nessuna partita valida trovata.');
    return;
  }

  print('');
  print('Partite selezionate: ${selected.length}');

  final builder = MatchDossierBuilder();

  var completed = 0;

  var baselineHits = 0;
  var momentumHits = 0;

  var baselineBrierTotal = 0.0;
  var momentumBrierTotal = 0.0;

  var baselineLogLossTotal = 0.0;
  var momentumLogLossTotal = 0.0;

  try {
    for (final match in selected) {
      final raw = rawByFixture[match.fixtureId];

      if (raw == null) {
        continue;
      }

      final actual = _actualResult(raw);

      if (actual == null) {
        continue;
      }

      print('');
      print('============================================================');
      print('${match.homeTeam} - ${match.awayTeam}');
      print('${match.league} (${match.country})');
      print('Fixture: ${match.fixtureId}');
      print(
        'Risultato reale: '
        '${actual.homeGoals}-${actual.awayGoals} '
        '(${actual.outcome})',
      );
      print('============================================================');

      final dossier = await builder.build(match);

      if (dossier == null) {
        print('Dossier non disponibile.');
        continue;
      }

      final momentumInput = GoalVdLineMatchInputAdapter.fromDossier(
        match: match,
        dossier: dossier,
        simulations: 20000,
      );

      final baselineHome = _baselineTeam(
        team: momentumInput.home,
        form: dossier.homeForm,
      );

      final baselineAway = _baselineTeam(
        team: momentumInput.away,
        form: dossier.awayForm,
      );

      final baselineInput = GoalVdLineMatchEngineInput(
        fixtureId: momentumInput.fixtureId,
        home: baselineHome,
        away: baselineAway,
        competitionWeight: momentumInput.competitionWeight,
        simulations: 20000,
      );

      final baseline = GoalVdLineMatchEngine.simulate(baselineInput);

      final momentum = GoalVdLineMatchEngine.simulate(momentumInput);

      final baselineBrier = _brier(baseline, actual.outcome);

      final momentumBrier = _brier(momentum, actual.outcome);

      final baselineLogLoss = _logLoss(baseline, actual.outcome);

      final momentumLogLoss = _logLoss(momentum, actual.outcome);

      final baselinePrediction = _bestOutcome(baseline);

      final momentumPrediction = _bestOutcome(momentum);

      if (baselinePrediction == actual.outcome) {
        baselineHits++;
      }

      if (momentumPrediction == actual.outcome) {
        momentumHits++;
      }

      completed++;

      baselineBrierTotal += baselineBrier;
      momentumBrierTotal += momentumBrier;

      baselineLogLossTotal += baselineLogLoss;
      momentumLogLossTotal += momentumLogLoss;

      print('');
      print('SENZA MOMENTUM');
      _printProbabilities(baseline);

      print('Pronostico: $baselinePrediction');

      print('Brier: ${baselineBrier.toStringAsFixed(4)}');

      print(
        'Log loss: '
        '${baselineLogLoss.toStringAsFixed(4)}',
      );

      print('');
      print('CON MOMENTUM');
      _printProbabilities(momentum);

      print('Pronostico: $momentumPrediction');

      print('Brier: ${momentumBrier.toStringAsFixed(4)}');

      print(
        'Log loss: '
        '${momentumLogLoss.toStringAsFixed(4)}',
      );

      print('');
      print(
        'Differenza Brier: '
        '${_signed(momentumBrier - baselineBrier)}',
      );

      if (momentumBrier < baselineBrier) {
        print('→ Momentum MIGLIORE');
      } else if (momentumBrier > baselineBrier) {
        print('→ Baseline MIGLIORE');
      } else {
        print('→ Identici');
      }
    }
  } finally {
    builder.dispose();
  }

  print('');
  print('============================================================');
  print('RISULTATO MINI BACKTEST');
  print('============================================================');

  if (completed == 0) {
    print('Nessuna analisi completata.');
    return;
  }

  final baselineBrier = baselineBrierTotal / completed;

  final momentumBrier = momentumBrierTotal / completed;

  final baselineLogLoss = baselineLogLossTotal / completed;

  final momentumLogLoss = momentumLogLossTotal / completed;

  print('Partite: $completed');

  print('');
  print(
    'Pronostico corretto baseline: '
    '$baselineHits/$completed',
  );

  print(
    'Pronostico corretto momentum: '
    '$momentumHits/$completed',
  );

  print('');
  print(
    'Brier medio baseline: '
    '${baselineBrier.toStringAsFixed(4)}',
  );

  print(
    'Brier medio momentum: '
    '${momentumBrier.toStringAsFixed(4)}',
  );

  print('');
  print(
    'Log loss medio baseline: '
    '${baselineLogLoss.toStringAsFixed(4)}',
  );

  print(
    'Log loss medio momentum: '
    '${momentumLogLoss.toStringAsFixed(4)}',
  );

  print('');

  if (momentumBrier < baselineBrier) {
    print(
      'RISULTATO: Form Momentum migliore '
      'su questo campione.',
    );
  } else if (momentumBrier > baselineBrier) {
    print(
      'RISULTATO: baseline migliore '
      'su questo campione.',
    );
  } else {
    print('RISULTATO: nessuna differenza.');
  }

  print('============================================================');
}

GoalVdLineTeamState _baselineTeam({
  required GoalVdLineTeamState team,
  required Map<String, dynamic> form,
}) {
  final snapshot = _parseRecent(teamName: team.teamName, form: form);

  if (snapshot.matches <= 0) {
    return team;
  }

  final formStrength =
      (((snapshot.wins * 3 + snapshot.draws) / (snapshot.matches * 3)) * 100.0)
          .clamp(0.0, 100.0)
          .toDouble();

  return GoalVdLineTeamState(
    teamId: team.teamId,
    teamName: team.teamName,
    structuralStrength: team.structuralStrength,
    squadStrength: team.squadStrength,
    attackStrength: team.attackStrength,
    defenseStrength: team.defenseStrength,
    recentFormStrength: formStrength,
    venueStrength: team.venueStrength,
    motivationStrength: team.motivationStrength,
    availabilityStrength: team.availabilityStrength,
    goalsForPerMatch: team.goalsForPerMatch,
    goalsAgainstPerMatch: team.goalsAgainstPerMatch,
    recentGoalsForPerMatch: snapshot.goalsFor / snapshot.matches,
    recentGoalsAgainstPerMatch: snapshot.goalsAgainst / snapshot.matches,
    injuredPlayers: team.injuredPlayers,
    suspendedPlayers: team.suspendedPlayers,
    unavailablePlayers: team.unavailablePlayers,
    contextAdjustment: team.contextAdjustment,
    lineupAvailable: team.lineupAvailable,
    dataConfidence: team.dataConfidence,
    contextNotes: team.contextNotes,
  );
}

_RecentSnapshot _parseRecent({
  required String teamName,
  required Map<String, dynamic> form,
}) {
  final rawMatches = form['matches'];

  if (rawMatches is! List) {
    return const _RecentSnapshot();
  }

  final team = teamName.trim().toLowerCase();

  final pattern = RegExp(r'(\d+)\s*-\s*(\d+)');

  var matches = 0;
  var wins = 0;
  var draws = 0;
  var goalsFor = 0;
  var goalsAgainst = 0;

  for (final raw in rawMatches) {
    final text = raw.toString().trim();

    final score = pattern.firstMatch(text);

    if (score == null) {
      continue;
    }

    final homeGoals = int.tryParse(score.group(1) ?? '');

    final awayGoals = int.tryParse(score.group(2) ?? '');

    if (homeGoals == null || awayGoals == null) {
      continue;
    }

    final before = text.substring(0, score.start).trim().toLowerCase();

    final after = text.substring(score.end).trim().toLowerCase();

    final int scored;
    final int conceded;

    if (before.contains(team)) {
      scored = homeGoals;
      conceded = awayGoals;
    } else if (after.contains(team)) {
      scored = awayGoals;
      conceded = homeGoals;
    } else {
      continue;
    }

    matches++;
    goalsFor += scored;
    goalsAgainst += conceded;

    if (scored > conceded) {
      wins++;
    } else if (scored == conceded) {
      draws++;
    }
  }

  return _RecentSnapshot(
    matches: matches,
    wins: wins,
    draws: draws,
    goalsFor: goalsFor,
    goalsAgainst: goalsAgainst,
  );
}

_ActualResult? _actualResult(Map<String, dynamic> raw) {
  final fixture = raw['fixture'];
  final goals = raw['goals'];

  if (fixture is! Map<String, dynamic> || goals is! Map<String, dynamic>) {
    return null;
  }

  final status = fixture['status'];

  if (status is! Map<String, dynamic>) {
    return null;
  }

  final short = status['short']?.toString().toUpperCase() ?? '';

  const finished = {'FT', 'AET', 'PEN', 'AWD', 'WO'};

  if (!finished.contains(short)) {
    return null;
  }

  final home = _nullableInt(goals['home']);
  final away = _nullableInt(goals['away']);

  if (home == null || away == null) {
    return null;
  }

  final outcome = home > away
      ? '1'
      : home < away
      ? '2'
      : 'X';

  return _ActualResult(homeGoals: home, awayGoals: away, outcome: outcome);
}

double _brier(GoalVdLineMatchEngineResult result, String actual) {
  final actualHome = actual == '1' ? 1.0 : 0.0;
  final actualDraw = actual == 'X' ? 1.0 : 0.0;
  final actualAway = actual == '2' ? 1.0 : 0.0;

  final homeError = result.homeWinProbability - actualHome;

  final drawError = result.drawProbability - actualDraw;

  final awayError = result.awayWinProbability - actualAway;

  return (homeError * homeError) +
      (drawError * drawError) +
      (awayError * awayError);
}

double _logLoss(GoalVdLineMatchEngineResult result, String actual) {
  final probability = switch (actual) {
    '1' => result.homeWinProbability,
    'X' => result.drawProbability,
    '2' => result.awayWinProbability,
    _ => 0.000001,
  };

  return -math.log(probability.clamp(0.000001, 0.999999));
}

String _bestOutcome(GoalVdLineMatchEngineResult result) {
  if (result.homeWinProbability >= result.drawProbability &&
      result.homeWinProbability >= result.awayWinProbability) {
    return '1';
  }

  if (result.awayWinProbability >= result.homeWinProbability &&
      result.awayWinProbability >= result.drawProbability) {
    return '2';
  }

  return 'X';
}

void _printProbabilities(GoalVdLineMatchEngineResult result) {
  print(
    '1 ${result.homeWinPercent.toStringAsFixed(1)}% | '
    'X ${result.drawPercent.toStringAsFixed(1)}% | '
    '2 ${result.awayWinPercent.toStringAsFixed(1)}%',
  );

  print(
    'xG '
    '${result.expectedHomeGoals.toStringAsFixed(2)} - '
    '${result.expectedAwayGoals.toStringAsFixed(2)}',
  );
}

String _signed(double value) {
  final prefix = value >= 0 ? '+' : '';

  return '$prefix${value.toStringAsFixed(4)}';
}

int _toInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  return int.tryParse(value.toString());
}

class _RecentSnapshot {
  final int matches;
  final int wins;
  final int draws;
  final int goalsFor;
  final int goalsAgainst;

  const _RecentSnapshot({
    this.matches = 0,
    this.wins = 0,
    this.draws = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
  });
}

class _ActualResult {
  final int homeGoals;
  final int awayGoals;
  final String outcome;

  const _ActualResult({
    required this.homeGoals,
    required this.awayGoals,
    required this.outcome,
  });
}
