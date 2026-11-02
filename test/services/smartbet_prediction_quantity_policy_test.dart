import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_prediction_quantity_policy.dart';

void main() {
  test('Risultati del giorno richiede cinque selezioni', () {
    expect(SmartBetPredictionQuantityPolicy.dailyTarget, 5);
  });

  test('non forza un pool di analisi senza candidati', () {
    expect(SmartBetPredictionQuantityPolicy.dailyAiPoolSize(0), 0);
    expect(SmartBetPredictionQuantityPolicy.dailyAiPoolSize(3), 3);
  });

  test('il pool giornaliero non supera 5 + 3 riserve', () {
    expect(SmartBetPredictionQuantityPolicy.dailyAiPoolSize(8), 8);
    expect(SmartBetPredictionQuantityPolicy.dailyAiPoolSize(50), 8);
  });

  test('solo 5 a 10 marcatori sono selezionabili', () {
    expect(SmartBetPredictionQuantityPolicy.scorerCounts, [5, 6, 7, 8, 9, 10]);
  });

  test('con 5 marcatori analizza 6 partite idonee', () {
    expect(SmartBetPredictionQuantityPolicy.scorerMatchesToScan(5), 6);
  });

  test('con 10 marcatori amplia la ricerca a 10 partite', () {
    expect(SmartBetPredictionQuantityPolicy.scorerMatchesToScan(10), 10);
  });

  test('un input oltre i limiti non allarga la scansione', () {
    expect(SmartBetPredictionQuantityPolicy.scorerMatchesToScan(3), 6);
    expect(SmartBetPredictionQuantityPolicy.scorerMatchesToScan(20), 10);
  });
}
