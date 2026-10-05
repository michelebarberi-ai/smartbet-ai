// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/ai/goalvdline_draw_suitability.dart';
import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/ai/goalvdline_match_input_adapter.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/football_api_service.dart';
import '../lib/services/match_dossier_builder.dart';

Future<void> main() async {
  final date = DateTime(2026, 9, 20);

  print('');
  print('============================================================');
  print('GOALVDLINE - BACKTEST DRAW SUITABILITY');
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

  final selected = candidates.take(6).toList();

  if (selected.isEmpty) {
    print('Nessuna partita valida trovata.');
    return;
  }

  print('');
  print('Partite selezionate: ${selected.length}');

  final builder = MatchDossierBuilder();

  final results = <_DrawTestResult>[];

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

      final input = GoalVdLineMatchInputAdapter.fromDossier(
        match: match,
        dossier: dossier,
        simulations: 20000,
      );

      final simulation = GoalVdLineMatchEngine.simulate(input);

      final draw = GoalVdLineDrawSuitability.evaluate(
        dossier: dossier,
        simulation: simulation,
      );

      results.add(
        _DrawTestResult(
          match: '${match.homeTeam} - ${match.awayTeam}',
          actual: actual.outcome,
          homeGoals: actual.homeGoals,
          awayGoals: actual.awayGoals,
          score: draw.score,
          level: draw.level,
          simulatedDrawProbability: simulation.drawPercent,
          balanceScore: draw.balanceScore,
          seasonDrawScore: draw.seasonDrawScore,
          venueDrawScore: draw.venueDrawScore,
          lowScoringScore: draw.lowScoringScore,
          simulatedDrawScore: draw.simulatedDrawScore,
        ),
      );

      print('');
      print(
        'Draw Suitability: '
        '${draw.score}/100 (${draw.level})',
      );

      print(
        'Probabilità X simulatore: '
        '${simulation.drawPercent.toStringAsFixed(1)}%',
      );

      print('');
      print(
        'Equilibrio: '
        '${draw.balanceScore.toStringAsFixed(1)}',
      );

      print(
        'Pareggi stagionali: '
        '${draw.seasonDrawScore.toStringAsFixed(1)}',
      );

      print(
        'Pareggi casa/trasferta: '
        '${draw.venueDrawScore.toStringAsFixed(1)}',
      );

      print(
        'Basso volume gol: '
        '${draw.lowScoringScore.toStringAsFixed(1)}',
      );

      print(
        'Score X simulatore: '
        '${draw.simulatedDrawScore.toStringAsFixed(1)}',
      );
    }
  } finally {
    builder.dispose();
  }

  print('');
  print('============================================================');
  print('CLASSIFICA DRAW SUITABILITY');
  print('============================================================');

  results.sort((a, b) => b.score.compareTo(a.score));

  for (final result in results) {
    final marker = result.actual == 'X' ? '✅ X' : '❌ ${result.actual}';

    print(
      '${result.score.toString().padLeft(3)} | '
      '$marker | '
      '${result.match} | '
      '${result.homeGoals}-${result.awayGoals} | '
      'X sim ${result.simulatedDrawProbability.toStringAsFixed(1)}%',
    );
  }

  final draws = results.where((item) => item.actual == 'X').toList();

  final nonDraws = results.where((item) => item.actual != 'X').toList();

  print('');
  print('============================================================');
  print('RISULTATO');
  print('============================================================');

  print('Partite analizzate: ${results.length}');
  print('Pareggi reali: ${draws.length}');
  print('Non pareggi: ${nonDraws.length}');

  print('');

  if (draws.isNotEmpty) {
    print(
      'Draw Suitability medio nei pareggi: '
      '${_average(draws.map((e) => e.score.toDouble())).toStringAsFixed(1)}',
    );
  }

  if (nonDraws.isNotEmpty) {
    print(
      'Draw Suitability medio nei non-pareggi: '
      '${_average(nonDraws.map((e) => e.score.toDouble())).toStringAsFixed(1)}',
    );
  }

  final highSuitability = results.where((item) => item.score >= 60).toList();

  final highDraws = highSuitability.where((item) => item.actual == 'X').length;

  print('');
  print(
    'Partite con Draw Suitability >= 60: '
    '${highSuitability.length}',
  );

  print(
    'Di queste terminate X: '
    '$highDraws',
  );

  if (highSuitability.isNotEmpty) {
    final hitRate = highDraws / highSuitability.length * 100.0;

    print(
      'Tasso X nel gruppo >=60: '
      '${hitRate.toStringAsFixed(1)}%',
    );
  }

  print('============================================================');
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

class _DrawTestResult {
  final String match;
  final String actual;

  final int homeGoals;
  final int awayGoals;

  final int score;
  final String level;

  final double simulatedDrawProbability;

  final double balanceScore;
  final double seasonDrawScore;
  final double venueDrawScore;
  final double lowScoringScore;
  final double simulatedDrawScore;

  const _DrawTestResult({
    required this.match,
    required this.actual,
    required this.homeGoals,
    required this.awayGoals,
    required this.score,
    required this.level,
    required this.simulatedDrawProbability,
    required this.balanceScore,
    required this.seasonDrawScore,
    required this.venueDrawScore,
    required this.lowScoringScore,
    required this.simulatedDrawScore,
  });
}
