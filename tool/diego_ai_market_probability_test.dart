// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/repositories/match_repository.dart';
import '../lib/services/diego_ai_market_probability_service.dart';
import '../lib/services/diego_ai_service.dart';

Future<void> main() async {
  final matches = await MatchRepository.getMatchesByDate(DateTime(2026, 10, 4));

  final match = matches.firstWhere((item) => item.fixtureId == 1569956);

  final service = DiegoAiService();
  const marketService = DiegoAiMarketProbabilityService();

  try {
    final analysis = await service.analyze(match, simulations: 20000);

    if (analysis == null) {
      print('Analisi DiegoAI non disponibile.');
      return;
    }

    final markets = marketService.ranked(analysis.engine);

    print('');
    print('============================================================');
    print('DIEGOAI - PROBABILITÀ MULTI-MERCATO');
    print('${match.homeTeam} - ${match.awayTeam}');
    print('============================================================');

    for (final item in markets) {
      print(
        '${item.market.padRight(10)} '
        '${item.percent.toStringAsFixed(1)}%',
      );
    }

    print('============================================================');
  } finally {
    service.dispose();
  }
}
