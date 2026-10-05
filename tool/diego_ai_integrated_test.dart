// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/repositories/match_repository.dart';
import '../lib/services/diego_ai_service.dart';

Future<void> main() async {
  final matches = await MatchRepository.getMatchesByDate(DateTime(2026, 10, 4));

  final match = matches.firstWhere((item) => item.fixtureId == 1569956);

  final diego = DiegoAiService();

  try {
    final analysis = await diego.analyze(match, simulations: 20000);

    if (analysis == null) {
      throw StateError('Analisi DiegoAI non disponibile.');
    }

    print('');
    print('============================================================');
    print('DIEGOAI - TEST INTEGRATO');
    print('${match.homeTeam} - ${match.awayTeam}');
    print('============================================================');

    print('');
    print('1X2');
    print('1 ${(analysis.homeProbability * 100).toStringAsFixed(1)}%');
    print('X ${(analysis.drawProbability * 100).toStringAsFixed(1)}%');
    print('2 ${(analysis.awayProbability * 100).toStringAsFixed(1)}%');

    print('');
    print('Data confidence: ${analysis.dataConfidence}/100');
    print(
      'Prediction confidence: '
      '${analysis.predictionConfidence}/100',
    );

    print('');
    print('Mercati disponibili: ${analysis.markets.length}');

    for (final market in analysis.markets) {
      print(
        '${market.market.padRight(10)} '
        '${market.percent.toStringAsFixed(1)}%',
      );
    }

    print('');
    print('VALUE MULTI-MERCATO');

    for (final item in analysis.multiMarketValue.markets) {
      print(
        '${item.market.padRight(10)} | '
        'P ${(item.aiProbability * 100).toStringAsFixed(1)}% | '
        'Conf ${item.marketConfidence} | '
        'Odd ${item.odd.toStringAsFixed(2)} | '
        'Edge ${(item.edge * 100).toStringAsFixed(1)} | '
        'EV ${(item.expectedValue * 100).toStringAsFixed(1)} | '
        '${item.classification}',
      );
    }

    print('');
    print('MIGLIOR VALUE');

    final best = analysis.bestMultiMarketValue;

    if (best == null) {
      print('Nessun value qualificato.');
    } else {
      print(
        '${best.market} @ ${best.odd.toStringAsFixed(2)} | '
        'Conf ${best.marketConfidence} | '
        '${best.classification} | '
        'EV ${(best.expectedValue * 100).toStringAsFixed(1)}%',
      );
    }

    // Controlli base di coerenza.
    if (analysis.markets.isEmpty) {
      throw StateError('Catalogo mercati vuoto.');
    }

    if (analysis.multiMarketValue.markets.isEmpty) {
      throw StateError('Value multi-mercato vuoto.');
    }

    print('');
    print('DIEGOAI INTEGRATA CORRETTAMENTE.');
    print('============================================================');
  } finally {
    diego.dispose();
  }
}
