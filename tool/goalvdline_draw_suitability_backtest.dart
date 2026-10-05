// ignore_for_file: avoid_print, avoid_relative_lib_imports

import 'dart:convert';

import '../lib/ai/goalvdline_draw_suitability.dart';
import '../lib/ai/goalvdline_match_engine.dart';
import '../lib/ai/goalvdline_match_input_adapter.dart';
import '../lib/models/match_dossier.dart';
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

  final selected = candidates.take(30).toList();

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

      final dossier = await builder.build(
        match,
        backtestSafe: true,
        backtestCurrentSeasonMinMatches: 10,
      );

      if (dossier == null) {
        print('Dossier non disponibile.');
        continue;
      }

      final backtestDossier = _sanitizeHistoricalDossier(dossier);

      print(
        'Confidence backtest solo-statistica: '
        '${backtestDossier.dataConfidence}%',
      );

      final input = GoalVdLineMatchInputAdapter.fromDossier(
        match: match,
        dossier: backtestDossier,
        simulations: 20000,
      );

      final simulation = GoalVdLineMatchEngine.simulate(input);

      final drawV1 = GoalVdLineDrawSuitability.evaluate(
        dossier: backtestDossier,
        simulation: simulation,
      );

      final drawV2 = GoalVdLineDrawSuitability.evaluateV2(
        dossier: backtestDossier,
        simulation: simulation,
      );

      final xgDifference =
          (simulation.expectedHomeGoals - simulation.expectedAwayGoals).abs();

      final winProbabilityDifference =
          (simulation.homeWinPercent - simulation.awayWinPercent).abs();

      final featureRow = <String, dynamic>{
        'date': match.date,
        'fixtureId': match.fixtureId,
        'competition': match.league,
        'country': match.country,
        'homeTeam': match.homeTeam,
        'awayTeam': match.awayTeam,
        'actual': actual.outcome,
        'actualDraw': actual.outcome == 'X' ? 1 : 0,
        'homeGoals': actual.homeGoals,
        'awayGoals': actual.awayGoals,
        'aiWeight': match.aiWeight,

        // Probabilità simulatore
        'homeWinProbability': simulation.homeWinPercent,
        'drawProbability': simulation.drawPercent,
        'awayWinProbability': simulation.awayWinPercent,
        'winProbabilityDifference': winProbabilityDifference,

        // Expected Goals
        'expectedHomeGoals': simulation.expectedHomeGoals,
        'expectedAwayGoals': simulation.expectedAwayGoals,
        'expectedTotalGoals': simulation.expectedTotalGoals,
        'xgDifference': xgDifference,

        // Mercati gol
        'under25Probability': simulation.under25Probability * 100.0,
        'over25Probability': simulation.over25Probability * 100.0,

        // Campioni storici stagione
        'homeSeasonMatches': _toInt(
          backtestDossier.homeStatistics['matchesPlayed'],
        ),
        'homeSeasonDraws': _toInt(backtestDossier.homeStatistics['draws']),
        'awaySeasonMatches': _toInt(
          backtestDossier.awayStatistics['matchesPlayed'],
        ),
        'awaySeasonDraws': _toInt(backtestDossier.awayStatistics['draws']),

        // Campioni casa / trasferta
        'homeVenueMatches': _toInt(backtestDossier.homeVenue['matches']),
        'homeVenueDraws': _toInt(backtestDossier.homeVenue['draws']),
        'awayVenueMatches': _toInt(backtestDossier.awayVenue['matches']),
        'awayVenueDraws': _toInt(backtestDossier.awayVenue['draws']),

        // Qualità dati
        'dataConfidence': backtestDossier.dataConfidence,

        // Benchmark V1
        'v1Score': drawV1.score,
        'v1BalanceScore': drawV1.balanceScore,
        'v1SeasonDrawScore': drawV1.seasonDrawScore,
        'v1VenueDrawScore': drawV1.venueDrawScore,
        'v1LowScoringScore': drawV1.lowScoringScore,
        'v1SimulatedDrawScore': drawV1.simulatedDrawScore,

        // Benchmark V2
        'v2Score': drawV2.score,
        'v2BalanceScore': drawV2.balanceScore,
        'v2SeasonDrawScore': drawV2.seasonDrawScore,
        'v2VenueDrawScore': drawV2.venueDrawScore,
        'v2LowScoringScore': drawV2.lowScoringScore,
        'v2SimulatedDrawScore': drawV2.simulatedDrawScore,
        'v2XgBalanceScore': drawV2.xgBalanceScore,
      };

      print('FEATURE_JSON ${jsonEncode(featureRow)}');

      results.add(
        _DrawTestResult(
          match: '${match.homeTeam} - ${match.awayTeam}',
          actual: actual.outcome,
          homeGoals: actual.homeGoals,
          awayGoals: actual.awayGoals,
          scoreV1: drawV1.score,
          scoreV2: drawV2.score,
          level: drawV2.level,
          simulatedDrawProbability: simulation.drawPercent,
          xgDifference: xgDifference,
          xgBalanceScore: drawV2.xgBalanceScore,
          balanceScore: drawV2.balanceScore,
          seasonDrawScore: drawV2.seasonDrawScore,
          venueDrawScore: drawV2.venueDrawScore,
          lowScoringScore: drawV2.lowScoringScore,
          simulatedDrawScore: drawV2.simulatedDrawScore,
        ),
      );

      print('');
      print(
        'Draw Suitability V1: '
        '${drawV1.score}/100 (${drawV1.level})',
      );

      print(
        'Draw Suitability V2: '
        '${drawV2.score}/100 (${drawV2.level})',
      );

      print(
        'Probabilità X simulatore: '
        '${simulation.drawPercent.toStringAsFixed(1)}%',
      );

      print(
        'Expected Goals: '
        '${simulation.expectedHomeGoals.toStringAsFixed(2)} - '
        '${simulation.expectedAwayGoals.toStringAsFixed(2)}',
      );

      print(
        'Differenza xG: '
        '${xgDifference.toStringAsFixed(2)}',
      );

      print(
        'Equilibrio xG: '
        '${drawV2.xgBalanceScore.toStringAsFixed(1)}',
      );

      print('');
      print(
        'Equilibrio: '
        '${drawV2.balanceScore.toStringAsFixed(1)}',
      );

      print(
        'Pareggi stagionali: '
        '${drawV2.seasonDrawScore.toStringAsFixed(1)}',
      );

      print(
        'Pareggi casa/trasferta: '
        '${drawV2.venueDrawScore.toStringAsFixed(1)}',
      );

      print(
        'Basso volume gol: '
        '${drawV2.lowScoringScore.toStringAsFixed(1)}',
      );

      print(
        'Score X simulatore: '
        '${drawV2.simulatedDrawScore.toStringAsFixed(1)}',
      );
    }
  } finally {
    builder.dispose();
  }

  print('');
  print('============================================================');
  print('CLASSIFICA DRAW SUITABILITY V2');
  print('============================================================');

  results.sort((a, b) => b.scoreV2.compareTo(a.scoreV2));

  for (final result in results) {
    final marker = result.actual == 'X' ? '✅ X' : '❌ ${result.actual}';

    print(
      'V2 ${result.scoreV2.toString().padLeft(3)} | '
      'V1 ${result.scoreV1.toString().padLeft(3)} | '
      '$marker | '
      '${result.match} | '
      '${result.homeGoals}-${result.awayGoals} | '
      'X ${result.simulatedDrawProbability.toStringAsFixed(1)}% | '
      'ΔxG ${result.xgDifference.toStringAsFixed(2)} | '
      'xGbal ${result.xgBalanceScore.toStringAsFixed(0)}',
    );
  }

  final draws = results.where((item) => item.actual == 'X').toList();
  final nonDraws = results.where((item) => item.actual != 'X').toList();

  print('');
  print('============================================================');
  print('CONFRONTO V1 VS V2');
  print('============================================================');

  print('Partite analizzate: ${results.length}');
  print('Pareggi reali: ${draws.length}');
  print('Non pareggi: ${nonDraws.length}');

  final baseRate = results.isEmpty
      ? 0.0
      : draws.length / results.length * 100.0;

  print(
    'Tasso X base: '
    '${baseRate.toStringAsFixed(1)}%',
  );

  if (draws.isNotEmpty) {
    print('');
    print(
      'V1 medio pareggi: '
      '${_average(draws.map((e) => e.scoreV1.toDouble())).toStringAsFixed(1)}',
    );

    print(
      'V2 medio pareggi: '
      '${_average(draws.map((e) => e.scoreV2.toDouble())).toStringAsFixed(1)}',
    );
  }

  if (nonDraws.isNotEmpty) {
    print(
      'V1 medio non-pareggi: '
      '${_average(nonDraws.map((e) => e.scoreV1.toDouble())).toStringAsFixed(1)}',
    );

    print(
      'V2 medio non-pareggi: '
      '${_average(nonDraws.map((e) => e.scoreV2.toDouble())).toStringAsFixed(1)}',
    );
  }

  print('');
  _printThresholdAnalysis(
    label: 'V1',
    results: results,
    scoreOf: (item) => item.scoreV1,
  );

  print('');
  _printThresholdAnalysis(
    label: 'V2',
    results: results,
    scoreOf: (item) => item.scoreV2,
  );

  print('============================================================');
}

void _printThresholdAnalysis({
  required String label,
  required List<_DrawTestResult> results,
  required int Function(_DrawTestResult item) scoreOf,
}) {
  final totalDraws = results.where((item) => item.actual == 'X').length;

  final baseRate = results.isEmpty ? 0.0 : totalDraws / results.length;

  print('------------------------------------------------------------');
  print('SOGLIE $label');
  print('------------------------------------------------------------');
  print('Soglia | N | X | Precision | Recall | Lift');

  for (final threshold in const [50, 55, 60, 65, 70]) {
    final selected = results
        .where((item) => scoreOf(item) >= threshold)
        .toList();

    final hits = selected.where((item) => item.actual == 'X').length;

    final precision = selected.isEmpty ? 0.0 : hits / selected.length;

    final recall = totalDraws == 0 ? 0.0 : hits / totalDraws;

    final lift = baseRate <= 0.0 ? 0.0 : precision / baseRate;

    print(
      '${threshold.toString().padLeft(6)} | '
      '${selected.length.toString().padLeft(2)} | '
      '${hits.toString().padLeft(2)} | '
      '${(precision * 100).toStringAsFixed(1).padLeft(8)}% | '
      '${(recall * 100).toStringAsFixed(1).padLeft(5)}% | '
      '${lift.toStringAsFixed(2)}x',
    );
  }
}

MatchDossier _sanitizeHistoricalDossier(MatchDossier dossier) {
  final homeConfidence = _statisticsConfidencePercent(
    dossier.homeStatistics['confidence'],
  );

  final awayConfidence = _statisticsConfidencePercent(
    dossier.awayStatistics['confidence'],
  );

  final availableConfidences = <double>[?homeConfidence, ?awayConfidence];

  final statisticsOnlyConfidence = availableConfidences.isEmpty
      ? dossier.dataConfidence
      : (availableConfidences.reduce((a, b) => a + b) /
                availableConfidences.length)
            .round()
            .clamp(0, 100);

  return MatchDossier(
    fixtureId: dossier.fixtureId,
    homeTeam: dossier.homeTeam,
    awayTeam: dossier.awayTeam,
    homeTeamId: dossier.homeTeamId,
    awayTeamId: dossier.awayTeamId,
    matchDate: dossier.matchDate,
    competition: dossier.competition,
    competitionId: dossier.competitionId,
    country: dossier.country,

    homeCurrentLeague: dossier.homeCurrentLeague,
    homeCurrentLeagueId: dossier.homeCurrentLeagueId,
    awayCurrentLeague: dossier.awayCurrentLeague,
    awayCurrentLeagueId: dossier.awayCurrentLeagueId,

    homeStatistics: dossier.homeStatistics,
    homeForm: dossier.homeForm,
    homeVenue: dossier.homeVenue,

    awayStatistics: dossier.awayStatistics,
    awayForm: dossier.awayForm,
    awayVenue: dossier.awayVenue,

    // Contesto non point-in-time: neutralizzato nel backtest.
    news: const [],
    injuries: const [],
    suspensions: const [],
    probableLineups: const [],
    marketInformation: const [],

    // H2H è già filtrato con fixtureDate < matchDate.
    headToHead: dossier.headToHead,

    dataConfidence: statisticsOnlyConfidence,
    preMatchOnly: true,
  );
}

double? _statisticsConfidencePercent(dynamic value) {
  if (value == null) {
    return null;
  }

  final double? parsed;

  if (value is num) {
    parsed = value.toDouble();
  } else {
    parsed = double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  if (parsed == null) {
    return null;
  }

  final normalized = parsed <= 1.0 ? parsed * 100.0 : parsed;

  return normalized.clamp(0.0, 100.0).toDouble();
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

  final int scoreV1;
  final int scoreV2;

  final String level;

  final double simulatedDrawProbability;

  final double xgDifference;
  final double xgBalanceScore;

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
    required this.scoreV1,
    required this.scoreV2,
    required this.level,
    required this.simulatedDrawProbability,
    required this.xgDifference,
    required this.xgBalanceScore,
    required this.balanceScore,
    required this.seasonDrawScore,
    required this.venueDrawScore,
    required this.lowScoringScore,
    required this.simulatedDrawScore,
  });
}
