// ignore_for_file: avoid_print, avoid_relative_lib_imports

import '../lib/services/odds_service.dart';
import '../lib/services/value_bet_calculator.dart';

void main() {
  const calculator = ValueBetCalculator();

  final odds = MatchOdds(
    fixtureId: 999999,
    referenceMarket: BookmakerOdds(
      fixtureId: 999999,
      bookmakerId: 1,
      bookmakerName: 'Test Bookmaker',
      homeOdd: 2.00,
      drawOdd: 3.40,
      awayOdd: 3.80,
      updatedAt: null,
    ),
    bestHome: const BestOdd(
      outcome: '1',
      odd: 2.10,
      bookmakerId: 2,
      bookmakerName: 'Best Home',
    ),
    bestDraw: const BestOdd(
      outcome: 'X',
      odd: 3.50,
      bookmakerId: 2,
      bookmakerName: 'Best Draw',
    ),
    bestAway: const BestOdd(
      outcome: '2',
      odd: 4.00,
      bookmakerId: 2,
      bookmakerName: 'Best Away',
    ),
    bookmakerCount: 2,
  );

  // ============================================================
  // 1. COMPATIBILITÀ CON IL VECCHIO FLUSSO
  // ============================================================

  final legacy = calculator.calculate(
    homeProbability: 60,
    drawProbability: 22,
    awayProbability: 18,
    dataConfidence: 80,
    odds: odds,
  );

  // ============================================================
  // 2. DATI BUONI MA PRONOSTICO POCO AFFIDABILE
  // ============================================================

  final lowPredictionConfidence = calculator.calculate(
    homeProbability: 60,
    drawProbability: 22,
    awayProbability: 18,
    dataConfidence: 80,
    predictionConfidence: 45,
    odds: odds,
  );

  // ============================================================
  // 3. CONFIDENCE MEDIA
  // ============================================================

  final mediumPredictionConfidence = calculator.calculate(
    homeProbability: 60,
    drawProbability: 22,
    awayProbability: 18,
    dataConfidence: 80,
    predictionConfidence: 60,
    odds: odds,
  );

  // ============================================================
  // 4. CONFIDENCE ALTA
  // ============================================================

  final highPredictionConfidence = calculator.calculate(
    homeProbability: 60,
    drawProbability: 22,
    awayProbability: 18,
    dataConfidence: 80,
    predictionConfidence: 75,
    odds: odds,
  );

  // ============================================================
  // 5. DATI SCARSI, ANCHE CON PRONOSTICO FORTE
  // ============================================================

  final poorData = calculator.calculate(
    homeProbability: 60,
    drawProbability: 22,
    awayProbability: 18,
    dataConfidence: 45,
    predictionConfidence: 80,
    odds: odds,
  );

  print('');
  print('============================================================');
  print('GOALVDLINE / DIEGOAI - VALUE ENGINE TEST');
  print('============================================================');

  _printResult('Fallback vecchio comportamento', legacy);

  _printResult('Prediction confidence 45', lowPredictionConfidence);

  _printResult('Prediction confidence 60', mediumPredictionConfidence);

  _printResult('Prediction confidence 75', highPredictionConfidence);

  _printResult('Data confidence 45 / prediction 80', poorData);

  // ============================================================
  // ASSERT
  // ============================================================

  if (legacy.home?.classification != 'STRONG VALUE') {
    throw StateError('Fallback compatibilità non mantiene STRONG VALUE.');
  }

  if (lowPredictionConfidence.home?.classification != 'NO VALUE') {
    throw StateError('Prediction confidence bassa non blocca il value.');
  }

  if (mediumPredictionConfidence.home?.classification != 'VALUE') {
    throw StateError('Prediction confidence 60 dovrebbe produrre VALUE.');
  }

  if (highPredictionConfidence.home?.classification != 'STRONG VALUE') {
    throw StateError(
      'Prediction confidence alta dovrebbe produrre STRONG VALUE.',
    );
  }

  if (poorData.home?.classification != 'NO VALUE') {
    throw StateError('Data confidence bassa deve bloccare il value.');
  }

  print('');
  print('TUTTI I CONTROLLI SUPERATI.');
  print('============================================================');
}

void _printResult(String label, ValueBetResult result) {
  final home = result.home;

  print('');
  print(label);
  print('----------------------------------------');

  if (home == null) {
    print('Nessun risultato casa.');
    return;
  }

  print('AI: ${(home.aiProbability * 100).toStringAsFixed(1)}%');

  print(
    'Mercato fair: '
    '${(home.fairMarketProbability * 100).toStringAsFixed(1)}%',
  );

  print('Edge: ${(home.edge * 100).toStringAsFixed(1)} p.p.');

  print('EV: ${(home.expectedValue * 100).toStringAsFixed(1)}%');

  print('Classificazione: ${home.classification}');
}
