// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/models/match_model.dart';
import '../lib/repositories/match_repository.dart';
import '../lib/services/diego_ai_service.dart';
import '../lib/services/value_bet_calculator.dart';

Future<void> main() async {
  final date = DateTime(2026, 10, 4);
  const fixtureId = 1569956;

  print('');
  print('============================================================');
  print('DIEGOAI - TEST COMPLETO PARTITA REALE');
  print('============================================================');

  final matches = await MatchRepository.getMatchesByDate(date);

  MatchModel? match;

  for (final item in matches) {
    if (item.fixtureId == fixtureId) {
      match = item;
      break;
    }
  }

  if (match == null) {
    print('Partita fixture $fixtureId non trovata.');
    return;
  }

  print('');
  print('${match.homeTeam} - ${match.awayTeam}');
  print('${match.league} - ${match.date}');

  final service = DiegoAiService();

  try {
    final analysis = await service.analyze(match, simulations: 20000);

    if (analysis == null) {
      print('');
      print('DiegoAI non ha potuto completare l’analisi.');
      return;
    }

    final engine = analysis.engine;

    print('');
    print('============================================================');
    print('DIEGOAI MATCH ENGINE');
    print('============================================================');

    print(
      'xG: '
      '${analysis.expectedHomeGoals.toStringAsFixed(2)} - '
      '${analysis.expectedAwayGoals.toStringAsFixed(2)}',
    );

    print('');
    print('1: ${(analysis.homeProbability * 100).toStringAsFixed(1)}%');
    print('X: ${(analysis.drawProbability * 100).toStringAsFixed(1)}%');
    print('2: ${(analysis.awayProbability * 100).toStringAsFixed(1)}%');

    print('');
    print(
      'Over 1.5: '
      '${(analysis.over15Probability * 100).toStringAsFixed(1)}%',
    );
    print(
      'Under 1.5: '
      '${(analysis.under15Probability * 100).toStringAsFixed(1)}%',
    );
    print(
      'Over 2.5: '
      '${(analysis.over25Probability * 100).toStringAsFixed(1)}%',
    );
    print(
      'Under 2.5: '
      '${(analysis.under25Probability * 100).toStringAsFixed(1)}%',
    );
    print(
      'Over 3.5: '
      '${(analysis.over35Probability * 100).toStringAsFixed(1)}%',
    );
    print(
      'Under 3.5: '
      '${(analysis.under35Probability * 100).toStringAsFixed(1)}%',
    );
    print(
      'Goal: '
      '${(analysis.goalProbability * 100).toStringAsFixed(1)}%',
    );
    print(
      'No Goal: '
      '${(analysis.noGoalProbability * 100).toStringAsFixed(1)}%',
    );

    print('');
    print('Data confidence: ${analysis.dataConfidence}/100');
    print(
      'Prediction confidence: '
      '${analysis.predictionConfidence}/100',
    );

    print('');
    print('RISULTATI ESATTI PIÙ PROBABILI');

    for (final score in engine.exactScores) {
      print(
        '${score.label}: '
        '${score.probabilityPercent.toStringAsFixed(1)}%',
      );
    }

    print('');
    print('============================================================');
    print('QUOTE / VALUE');
    print('============================================================');

    final odds = analysis.odds;

    if (odds == null) {
      print('Quote 1X2 non disponibili.');
    } else {
      print(
        'Bookmaker riferimento: '
        '${odds.referenceMarket.bookmakerName}',
      );

      print(
        'Margine bookmaker: '
        '${(odds.bookmakerMargin * 100).toStringAsFixed(1)}%',
      );

      print('');
      print(
        'Fair mercato 1: '
        '${(odds.fairHomeProbability * 100).toStringAsFixed(1)}%',
      );
      print(
        'Fair mercato X: '
        '${(odds.fairDrawProbability * 100).toStringAsFixed(1)}%',
      );
      print(
        'Fair mercato 2: '
        '${(odds.fairAwayProbability * 100).toStringAsFixed(1)}%',
      );

      print('');
      print(
        'Best odd 1: ${odds.bestHome.odd.toStringAsFixed(2)} '
        '(${odds.bestHome.bookmakerName})',
      );
      print(
        'Best odd X: ${odds.bestDraw.odd.toStringAsFixed(2)} '
        '(${odds.bestDraw.bookmakerName})',
      );
      print(
        'Best odd 2: ${odds.bestAway.odd.toStringAsFixed(2)} '
        '(${odds.bestAway.bookmakerName})',
      );
    }

    print('');
    _printValue('1', analysis.value.home);
    _printValue('X', analysis.value.draw);
    _printValue('2', analysis.value.away);

    print('');
    print('============================================================');
    print('MIGLIOR VALUE DIEGOAI');
    print('============================================================');

    final best = analysis.bestValue;

    if (best == null) {
      print('Nessun value qualificato.');
    } else {
      print('${best.outcome} @ ${best.bestOdd.toStringAsFixed(2)}');
      print('Classificazione: ${best.classification}');
      print('Edge: ${(best.edge * 100).toStringAsFixed(1)} p.p.');
      print('EV: ${(best.expectedValue * 100).toStringAsFixed(1)}%');
    }

    print('');
    print('============================================================');
    print('DIEGOAI TEST COMPLETATO');
    print('============================================================');
  } finally {
    service.dispose();
  }
}

void _printValue(String label, ValueBetOutcome? value) {
  if (value == null) {
    print('$label: non disponibile');
    return;
  }

  print(
    '$label | '
    'AI ${(value.aiProbability * 100).toStringAsFixed(1)}% | '
    'fair ${(value.fairMarketProbability * 100).toStringAsFixed(1)}% | '
    'edge ${(value.edge * 100).toStringAsFixed(1)} p.p. | '
    'EV ${(value.expectedValue * 100).toStringAsFixed(1)}% | '
    '${value.classification}',
  );
}
