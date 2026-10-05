// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/models/goalvdline_match_engine_models.dart';
import '../lib/services/diego_ai_multi_market_value_service.dart';
import '../lib/services/odds_service.dart';

void main() {
  const service = DiegoAiMultiMarketValueService();

  print('');
  print('============================================================');
  print('DIEGOAI - MULTI MARKET VALUE RULES TEST');
  print('============================================================');

  // ============================================================
  // MERCATI BINARI
  // ============================================================

  _expect(
    service: service,
    label: 'Confidence bassa anche con EV forte',
    probability: 0.60,
    odd: 2.00,
    dataConfidence: 80,
    expected: 'NO VALUE',
  );

  _expect(
    service: service,
    label: 'Weak Value',
    probability: 0.75,
    odd: 1.42,
    dataConfidence: 80,
    expected: 'WEAK VALUE',
  );

  _expect(
    service: service,
    label: 'Value',
    probability: 0.80,
    odd: 1.38,
    dataConfidence: 80,
    expected: 'VALUE',
  );

  _expect(
    service: service,
    label: 'Strong Value',
    probability: 0.85,
    odd: 1.35,
    dataConfidence: 80,
    expected: 'STRONG VALUE',
  );

  _expect(
    service: service,
    label: 'Dati insufficienti',
    probability: 0.85,
    odd: 1.35,
    dataConfidence: 45,
    expected: 'NO VALUE',
  );

  // ============================================================
  // 1X2: deve usare PREDICTION CONFIDENCE
  // ============================================================

  final engine1x2 = _engine(home: 0.60, draw: 0.25, away: 0.15, over15: 0.50);

  final odds1x2 = FixtureMarketOdds(
    fixtureId: 1,
    matchWinner: MatchOdds(
      fixtureId: 1,
      referenceMarket: const BookmakerOdds(
        fixtureId: 1,
        bookmakerId: 1,
        bookmakerName: 'Reference',
        homeOdd: 2.00,
        drawOdd: 3.20,
        awayOdd: 3.50,
        updatedAt: null,
      ),
      bestHome: const BestOdd(
        outcome: '1',
        odd: 2.20,
        bookmakerId: 2,
        bookmakerName: 'Best',
      ),
      bestDraw: const BestOdd(
        outcome: 'X',
        odd: 3.30,
        bookmakerId: 2,
        bookmakerName: 'Best',
      ),
      bestAway: const BestOdd(
        outcome: '2',
        odd: 3.60,
        bookmakerId: 2,
        bookmakerName: 'Best',
      ),
      bookmakerCount: 2,
    ),
    bestByOutcome: const {
      '1': BestOdd(
        outcome: '1',
        odd: 2.20,
        bookmakerId: 2,
        bookmakerName: 'Best',
      ),
    },
    bookmakerCount: 2,
  );

  final lowPrediction = service.calculate(
    engine: engine1x2,
    odds: odds1x2,
    dataConfidence: 80,
    predictionConfidence: 45,
  );

  final highPrediction = service.calculate(
    engine: engine1x2,
    odds: odds1x2,
    dataConfidence: 80,
    predictionConfidence: 75,
  );

  final low1 = lowPrediction.markets.singleWhere((item) => item.market == '1');

  final high1 = highPrediction.markets.singleWhere(
    (item) => item.market == '1',
  );

  print('');
  print('1X2 con Prediction Confidence 45: ${low1.classification}');
  print('1X2 con Prediction Confidence 75: ${high1.classification}');

  if (low1.marketConfidence != 45 || low1.classification != 'NO VALUE') {
    throw StateError('1X2 non rispetta la Prediction Confidence bassa.');
  }

  if (high1.marketConfidence != 75 || high1.classification != 'STRONG VALUE') {
    throw StateError('1X2 non rispetta la Prediction Confidence alta.');
  }

  print('');
  print('TUTTI I CONTROLLI MULTI-MARKET SUPERATI.');
  print('============================================================');
}

void _expect({
  required DiegoAiMultiMarketValueService service,
  required String label,
  required double probability,
  required double odd,
  required int dataConfidence,
  required String expected,
}) {
  final engine = _engine(
    home: 0.40,
    draw: 0.30,
    away: 0.30,
    over15: probability,
  );

  final odds = FixtureMarketOdds(
    fixtureId: 1,
    matchWinner: null,
    bestByOutcome: {
      'OVER 1.5': BestOdd(
        outcome: 'OVER 1.5',
        odd: odd,
        bookmakerId: 1,
        bookmakerName: 'Test',
      ),
    },
    bookmakerCount: 1,
  );

  final result = service.calculate(
    engine: engine,
    odds: odds,
    dataConfidence: dataConfidence,
    predictionConfidence: 50,
  );

  final item = result.markets.single;

  print('');
  print(label);
  print(
    'P ${(item.aiProbability * 100).toStringAsFixed(1)}% | '
    'Conf ${item.marketConfidence} | '
    'Edge ${(item.edge * 100).toStringAsFixed(1)} | '
    'EV ${(item.expectedValue * 100).toStringAsFixed(1)} | '
    '${item.classification}',
  );

  if (item.classification != expected) {
    throw StateError(
      '$label: atteso $expected, trovato ${item.classification}.',
    );
  }
}

GoalVdLineMatchEngineResult _engine({
  required double home,
  required double draw,
  required double away,
  required double over15,
}) {
  return GoalVdLineMatchEngineResult(
    expectedHomeGoals: 1.40,
    expectedAwayGoals: 1.10,
    homeWinProbability: home,
    drawProbability: draw,
    awayWinProbability: away,
    over15Probability: over15,
    over25Probability: 0.50,
    over35Probability: 0.30,
    goalProbability: 0.50,
    dataConfidence: 80,
    predictionConfidence: 50,
    simulations: 20000,
    exactScores: const [],
  );
}
