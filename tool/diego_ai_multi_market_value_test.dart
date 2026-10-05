// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/repositories/match_repository.dart';
import '../lib/services/diego_ai_multi_market_value_service.dart';
import '../lib/services/diego_ai_service.dart';
import '../lib/services/odds_service.dart';

Future<void> main() async {
  final matches = await MatchRepository.getMatchesByDate(DateTime(2026, 10, 4));

  final match = matches.firstWhere((item) => item.fixtureId == 1569956);

  final diego = DiegoAiService();
  final oddsService = OddsService();
  const valueService = DiegoAiMultiMarketValueService();

  try {
    final analysis = await diego.analyze(match, simulations: 20000);

    if (analysis == null) {
      print('Analisi DiegoAI non disponibile.');
      return;
    }

    final fixtureOdds = await oddsService.getFixtureMarketOdds(
      fixtureId: match.fixtureId,
    );

    final result = valueService.calculate(
      engine: analysis.engine,
      odds: fixtureOdds,
      dataConfidence: analysis.dataConfidence,
      predictionConfidence: analysis.predictionConfidence,
    );

    print('');
    print('================================================================');
    print('DIEGOAI - MULTI MARKET VALUE TEST');
    print('${match.homeTeam} - ${match.awayTeam}');
    print('================================================================');

    print(
      'Data confidence: '
      '${analysis.dataConfidence}/100',
    );

    print(
      'Prediction confidence: '
      '${analysis.predictionConfidence}/100',
    );

    print('');
    print('MERCATO      AI      QUOTA   MERCATO   EDGE      EV       VALUE');
    print('----------------------------------------------------------------');

    for (final item in result.markets) {
      final comparison =
          item.comparisonType == DiegoAiMarketComparisonType.fairMarket
          ? 'fair'
          : 'implied';

      print(
        '${item.market.padRight(11)} '
        '${(item.aiProbability * 100).toStringAsFixed(1).padLeft(5)}%  '
        '${item.marketConfidence.toString().padLeft(3)}   '
        '${item.odd.toStringAsFixed(2).padLeft(5)}   '
        '${(item.marketProbability * 100).toStringAsFixed(1).padLeft(5)}%  '
        '${_signed(item.edge * 100).padLeft(6)}  '
        '${_signed(item.expectedValue * 100).padLeft(7)}  '
        '${item.classification} [$comparison]',
      );
    }

    print('');
    print('================================================================');
    print('MIGLIORI VALUE');
    print('================================================================');

    if (result.valueMarkets.isEmpty) {
      print('Nessun mercato qualificato come value.');
    } else {
      for (final item in result.valueMarkets) {
        print(
          '${item.market} @ ${item.odd.toStringAsFixed(2)} | '
          '${item.classification} | '
          'Edge ${_signed(item.edge * 100)} | '
          'EV ${_signed(item.expectedValue * 100)}',
        );
      }
    }

    print('');
    print('================================================================');
  } finally {
    diego.dispose();
    oddsService.dispose();
  }
}

String _signed(double value) {
  final prefix = value >= 0 ? '+' : '';

  return '$prefix${value.toStringAsFixed(1)}%';
}
