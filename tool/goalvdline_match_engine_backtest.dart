// ignore_for_file: avoid_print, avoid_relative_lib_imports

import 'dart:io';
import 'dart:math' as math;

import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/ai/goalvdline_match_input_adapter.dart';
import '../lib/models/goalvdline_match_engine_models.dart';
import '../lib/models/match_model.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/football_api_service.dart';
import '../lib/services/match_dossier_builder.dart';

Future<void> main(List<String> args) async {
  final requestedLimit = args.isNotEmpty ? int.tryParse(args.first) ?? 10 : 10;

  final limit = requestedLimit.clamp(1, 100);

  final dates = <DateTime>[
    DateTime(2026, 9, 12),
    DateTime(2026, 9, 13),
    DateTime(2026, 9, 19),
    DateTime(2026, 9, 20),
    DateTime(2026, 9, 26),
    DateTime(2026, 9, 27),
  ];

  print('');
  print('============================================================');
  print('GOALVDLINE MATCH ENGINE - BACKTEST');
  print('Target: $limit partite');
  print('============================================================');

  final candidatesByDate = <List<_BacktestCandidate>>[];

  for (final date in dates) {
    print('');
    print('Carico ${_dateLabel(date)}...');

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

    final daily = <_BacktestCandidate>[];

    for (final match in matches) {
      if (!match.hasTeamIds ||
          match.fixtureId <= 0 ||
          match.isFriendly ||
          match.aiWeight < 0.85) {
        continue;
      }

      final raw = rawByFixture[match.fixtureId];

      if (raw == null) {
        continue;
      }

      final actual = _actualResult(raw);

      if (actual == null) {
        continue;
      }

      daily.add(_BacktestCandidate(match: match, actual: actual));
    }

    daily.sort((a, b) {
      final weight = b.match.aiWeight.compareTo(a.match.aiWeight);

      if (weight != 0) {
        return weight;
      }

      return a.match.fixtureId.compareTo(b.match.fixtureId);
    });

    candidatesByDate.add(daily);
  }

  final candidates = <_BacktestCandidate>[];

  var round = 0;

  while (candidates.length < limit) {
    var added = false;

    for (final daily in candidatesByDate) {
      if (candidates.length >= limit) {
        break;
      }

      if (round >= daily.length) {
        continue;
      }

      candidates.add(daily[round]);
      added = true;
    }

    if (!added) {
      break;
    }

    round++;
  }

  print('');
  print('Candidate raccolte: ${candidates.length}');

  if (candidates.isEmpty) {
    print('Nessuna partita valida trovata.');
    return;
  }

  final builder = MatchDossierBuilder();

  final rows = <_BacktestRow>[];

  var failures = 0;

  try {
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final match = candidate.match;
      final actual = candidate.actual;

      print('');
      print(
        '[${index + 1}/${candidates.length}] '
        '${match.homeTeam} - ${match.awayTeam} '
        '(${actual.homeGoals}-${actual.awayGoals})',
      );

      try {
        final dossier = await builder.build(match);

        if (dossier == null) {
          failures++;
          print('  → dossier non disponibile');
          continue;
        }

        final input = GoalVdLineMatchInputAdapter.fromDossier(
          match: match,
          dossier: dossier,
          simulations: 20000,
        );

        final result = GoalVdLineMatchEngine.simulate(input);

        final predictedOutcome = _bestOutcome(result);

        final outcomeHit = predictedOutcome == actual.outcome;

        final brier1x2 = _brier1x2(result, actual.outcome);

        final logLoss1x2 = _logLoss1x2(result, actual.outcome);

        final actualOver25 = (actual.homeGoals + actual.awayGoals) >= 3;

        final actualGoal = actual.homeGoals > 0 && actual.awayGoals > 0;

        final over25Brier = _binaryBrier(
          result.over25Probability,
          actualOver25,
        );

        final goalBrier = _binaryBrier(result.goalProbability, actualGoal);

        final exactTop1 =
            result.exactScores.isNotEmpty &&
            result.exactScores.first.homeGoals == actual.homeGoals &&
            result.exactScores.first.awayGoals == actual.awayGoals;

        final exactTop5 = result.exactScores.any(
          (score) =>
              score.homeGoals == actual.homeGoals &&
              score.awayGoals == actual.awayGoals,
        );

        rows.add(
          _BacktestRow(
            fixtureId: match.fixtureId,
            match: '${match.homeTeam} - ${match.awayTeam}',
            league: match.league,
            actualOutcome: actual.outcome,
            predictedOutcome: predictedOutcome,
            outcomeHit: outcomeHit,
            homeProbability: result.homeWinProbability,
            drawProbability: result.drawProbability,
            awayProbability: result.awayWinProbability,
            expectedHomeGoals: result.expectedHomeGoals,
            expectedAwayGoals: result.expectedAwayGoals,
            brier1x2: brier1x2,
            logLoss1x2: logLoss1x2,
            actualOver25: actualOver25,
            over25Probability: result.over25Probability,
            over25Brier: over25Brier,
            actualGoal: actualGoal,
            goalProbability: result.goalProbability,
            goalBrier: goalBrier,
            dataConfidence: result.dataConfidence,
            predictionConfidence: result.predictionConfidence,
            exactTop1: exactTop1,
            exactTop5: exactTop5,
          ),
        );

        print(
          '  → $predictedOutcome '
          '${outcomeHit ? "✓" : "✗"} | '
          '1 ${result.homeWinPercent.toStringAsFixed(1)} '
          'X ${result.drawPercent.toStringAsFixed(1)} '
          '2 ${result.awayWinPercent.toStringAsFixed(1)} | '
          'conf ${result.predictionConfidence}',
        );
      } catch (e) {
        failures++;
        print('  → ERRORE: $e');
      }
    }
  } finally {
    builder.dispose();
  }

  if (rows.isEmpty) {
    print('');
    print('Nessuna partita analizzata.');
    return;
  }

  await _writeCsv(rows);

  final hits = rows.where((row) => row.outcomeHit).length;

  final over25Hits = rows.where((row) {
    return (row.over25Probability >= 0.5) == row.actualOver25;
  }).length;

  final goalHits = rows.where((row) {
    return (row.goalProbability >= 0.5) == row.actualGoal;
  }).length;

  final avgBrier = _average(rows.map((e) => e.brier1x2));

  final avgLogLoss = _average(rows.map((e) => e.logLoss1x2));

  final avgOverBrier = _average(rows.map((e) => e.over25Brier));

  final avgGoalBrier = _average(rows.map((e) => e.goalBrier));

  final avgDataConfidence = _average(
    rows.map((e) => e.dataConfidence.toDouble()),
  );

  final avgPredictionConfidence = _average(
    rows.map((e) => e.predictionConfidence.toDouble()),
  );

  final exactTop1 = rows.where((row) => row.exactTop1).length;

  final exactTop5 = rows.where((row) => row.exactTop5).length;

  print('');
  print('============================================================');
  print('RISULTATO BACKTEST');
  print('============================================================');

  print('Partite analizzate: ${rows.length}');
  print('Fallimenti tecnici/dati: $failures');

  print('');
  print('--- 1X2 ---');

  print(
    'Esito principale corretto: '
    '$hits/${rows.length} '
    '(${(hits / rows.length * 100).toStringAsFixed(1)}%)',
  );

  print(
    'Brier medio 1X2: '
    '${avgBrier.toStringAsFixed(4)}',
  );

  print(
    'Log Loss media 1X2: '
    '${avgLogLoss.toStringAsFixed(4)}',
  );

  print('');
  print('--- OVER / UNDER 2.5 ---');

  print(
    'Classificazione corretta: '
    '$over25Hits/${rows.length} '
    '(${(over25Hits / rows.length * 100).toStringAsFixed(1)}%)',
  );

  print(
    'Brier medio O/U 2.5: '
    '${avgOverBrier.toStringAsFixed(4)}',
  );

  print('');
  print('--- GOAL / NO GOAL ---');

  print(
    'Classificazione corretta: '
    '$goalHits/${rows.length} '
    '(${(goalHits / rows.length * 100).toStringAsFixed(1)}%)',
  );

  print(
    'Brier medio Goal: '
    '${avgGoalBrier.toStringAsFixed(4)}',
  );

  print('');
  print('--- RISULTATO ESATTO ---');

  print(
    'Top 1 corretto: '
    '$exactTop1/${rows.length}',
  );

  print(
    'Nei Top 5: '
    '$exactTop5/${rows.length}',
  );

  print('');
  print('--- AFFIDABILITÀ ---');

  print(
    'Data confidence media: '
    '${avgDataConfidence.toStringAsFixed(1)}/100',
  );

  print(
    'Prediction confidence media: '
    '${avgPredictionConfidence.toStringAsFixed(1)}/100',
  );

  _printConfidenceBuckets(rows);

  print('');
  print(
    'CSV salvato in: '
    'tool/goalvdline_match_engine_backtest_results.csv',
  );

  print('============================================================');
}

void _printConfidenceBuckets(List<_BacktestRow> rows) {
  print('');
  print('Accuratezza per confidence:');

  const buckets = <_ConfidenceBucket>[
    _ConfidenceBucket(0, 49),
    _ConfidenceBucket(50, 59),
    _ConfidenceBucket(60, 69),
    _ConfidenceBucket(70, 79),
    _ConfidenceBucket(80, 100),
  ];

  for (final bucket in buckets) {
    final items = rows.where(
      (row) =>
          row.predictionConfidence >= bucket.min &&
          row.predictionConfidence <= bucket.max,
    );

    final list = items.toList();

    if (list.isEmpty) {
      continue;
    }

    final hits = list.where((row) => row.outcomeHit).length;

    print(
      '${bucket.min}-${bucket.max}: '
      '$hits/${list.length} '
      '(${(hits / list.length * 100).toStringAsFixed(1)}%)',
    );
  }
}

Future<void> _writeCsv(List<_BacktestRow> rows) async {
  final buffer = StringBuffer();

  buffer.writeln(
    'fixture_id,match,league,actual,predicted,hit,'
    'p1,px,p2,expected_home_goals,expected_away_goals,'
    'brier_1x2,log_loss,'
    'actual_over25,p_over25,brier_over25,'
    'actual_goal,p_goal,brier_goal,'
    'data_confidence,prediction_confidence,'
    'exact_top1,exact_top5',
  );

  for (final row in rows) {
    buffer.writeln(
      [
        row.fixtureId,
        _csv(row.match),
        _csv(row.league),
        row.actualOutcome,
        row.predictedOutcome,
        row.outcomeHit,
        row.homeProbability.toStringAsFixed(6),
        row.drawProbability.toStringAsFixed(6),
        row.awayProbability.toStringAsFixed(6),
        row.expectedHomeGoals.toStringAsFixed(6),
        row.expectedAwayGoals.toStringAsFixed(6),
        row.brier1x2.toStringAsFixed(6),
        row.logLoss1x2.toStringAsFixed(6),
        row.actualOver25,
        row.over25Probability.toStringAsFixed(6),
        row.over25Brier.toStringAsFixed(6),
        row.actualGoal,
        row.goalProbability.toStringAsFixed(6),
        row.goalBrier.toStringAsFixed(6),
        row.dataConfidence,
        row.predictionConfidence,
        row.exactTop1,
        row.exactTop5,
      ].join(','),
    );
  }

  await File(
    'tool/goalvdline_match_engine_backtest_results.csv',
  ).writeAsString(buffer.toString());
}

String _csv(String value) {
  return '"${value.replaceAll('"', '""')}"';
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

double _brier1x2(GoalVdLineMatchEngineResult result, String actual) {
  final h = actual == '1' ? 1.0 : 0.0;
  final d = actual == 'X' ? 1.0 : 0.0;
  final a = actual == '2' ? 1.0 : 0.0;

  final eh = result.homeWinProbability - h;
  final ed = result.drawProbability - d;
  final ea = result.awayWinProbability - a;

  return eh * eh + ed * ed + ea * ea;
}

double _logLoss1x2(GoalVdLineMatchEngineResult result, String actual) {
  final probability = switch (actual) {
    '1' => result.homeWinProbability,
    'X' => result.drawProbability,
    '2' => result.awayWinProbability,
    _ => 0.000001,
  };

  return -math.log(probability.clamp(0.000001, 0.999999));
}

double _binaryBrier(double probability, bool actual) {
  final target = actual ? 1.0 : 0.0;
  final error = probability - target;

  return error * error;
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

double _average(Iterable<double> values) {
  final list = values.toList();

  if (list.isEmpty) {
    return 0.0;
  }

  return list.reduce((a, b) => a + b) / list.length;
}

String _dateLabel(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
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

class _BacktestCandidate {
  final MatchModel match;
  final _ActualResult actual;

  const _BacktestCandidate({required this.match, required this.actual});
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

class _BacktestRow {
  final int fixtureId;
  final String match;
  final String league;

  final String actualOutcome;
  final String predictedOutcome;
  final bool outcomeHit;

  final double homeProbability;
  final double drawProbability;
  final double awayProbability;

  final double expectedHomeGoals;
  final double expectedAwayGoals;

  final double brier1x2;
  final double logLoss1x2;

  final bool actualOver25;
  final double over25Probability;
  final double over25Brier;

  final bool actualGoal;
  final double goalProbability;
  final double goalBrier;

  final int dataConfidence;
  final int predictionConfidence;

  final bool exactTop1;
  final bool exactTop5;

  const _BacktestRow({
    required this.fixtureId,
    required this.match,
    required this.league,
    required this.actualOutcome,
    required this.predictedOutcome,
    required this.outcomeHit,
    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
    required this.brier1x2,
    required this.logLoss1x2,
    required this.actualOver25,
    required this.over25Probability,
    required this.over25Brier,
    required this.actualGoal,
    required this.goalProbability,
    required this.goalBrier,
    required this.dataConfidence,
    required this.predictionConfidence,
    required this.exactTop1,
    required this.exactTop5,
  });
}

class _ConfidenceBucket {
  final int min;
  final int max;

  const _ConfidenceBucket(this.min, this.max);
}
