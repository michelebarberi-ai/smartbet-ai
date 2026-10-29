import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_asian_handicap_accounting_service.dart';
import 'package:smartbet_ai_new/services/smartbet_asian_handicap_settlement_service.dart';

void main() {
  SmartBetAsianHandicapAccounting? result(SmartBetAsianSettlement settlement) {
    return SmartBetAsianHandicapAccountingService.fromSettlement(settlement);
  }

  test('Vittoria: puntata interamente vincente', () {
    final value = result(SmartBetAsianSettlement.win)!;
    expect(value.winningFraction, 1.0);
    expect(value.refundedFraction, 0.0);
  });

  test('Mezza vittoria: meta vincente e meta rimborsata', () {
    final value = result(SmartBetAsianSettlement.halfWin)!;
    expect(value.winningFraction, 0.5);
    expect(value.refundedFraction, 0.5);
  });

  test('Push: intera puntata rimborsata', () {
    final value = result(SmartBetAsianSettlement.push)!;
    expect(value.refundedFraction, 1.0);
  });

  test('Mezza perdita: meta persa e meta rimborsata', () {
    final value = result(SmartBetAsianSettlement.halfLoss)!;
    expect(value.losingFraction, 0.5);
    expect(value.refundedFraction, 0.5);
  });

  test('Perdita: intera puntata persa', () {
    final value = result(SmartBetAsianSettlement.loss)!;
    expect(value.losingFraction, 1.0);
  });

  test('Unsupported: non genera liquidazione', () {
    expect(result(SmartBetAsianSettlement.unsupported), isNull);
  });

  test('Tutte le ripartizioni sommano a uno', () {
    for (final settlement in SmartBetAsianSettlement.values) {
      final value = result(settlement);
      if (value == null) continue;

      expect(
        value.winningFraction + value.refundedFraction + value.losingFraction,
        closeTo(1.0, 1e-10),
      );
    }
  });

  test('Quota 2.40: vittoria rende +1.40', () {
    expect(
      result(SmartBetAsianSettlement.win)!.profitUnitsForDecimalOdd(2.40),
      closeTo(1.40, 1e-10),
    );
  });

  test('Quota 2.40: mezza vittoria rende +0.70', () {
    expect(
      result(SmartBetAsianSettlement.halfWin)!.profitUnitsForDecimalOdd(2.40),
      closeTo(0.70, 1e-10),
    );
  });

  test('Rimborso: profitto zero', () {
    expect(
      result(SmartBetAsianSettlement.push)!.profitUnitsForDecimalOdd(2.40),
      0.0,
    );
  });

  test('Mezza perdita: profitto -0.50', () {
    expect(
      result(SmartBetAsianSettlement.halfLoss)!.profitUnitsForDecimalOdd(2.40),
      -0.5,
    );
  });

  test('Perdita: profitto -1.00', () {
    expect(
      result(SmartBetAsianSettlement.loss)!.profitUnitsForDecimalOdd(2.40),
      -1.0,
    );
  });

  test('Rifiuta quote mancanti o non valide', () {
    final value = result(SmartBetAsianSettlement.win)!;

    for (final odd in <double?>[
      null,
      0.0,
      1.0,
      -2.0,
      double.nan,
      double.infinity,
    ]) {
      expect(value.profitUnitsForDecimalOdd(odd), isNull);
    }
  });

  test('Risultato 2-1: ospite +1.25 = mezza vittoria', () {
    final value = SmartBetAsianHandicapAccountingService.evaluate(
      homeGoals: 2,
      awayGoals: 1,
      side: SmartBetAsianSide.away,
      handicap: 1.25,
    );

    expect(value?.settlement, SmartBetAsianSettlement.halfWin);
    expect(value?.profitUnitsForDecimalOdd(2.40), closeTo(0.70, 1e-10));
  });

  test('Draw No Bet: pareggio e handicap zero = rimborso', () {
    final value = SmartBetAsianHandicapAccountingService.evaluate(
      homeGoals: 1,
      awayGoals: 1,
      side: SmartBetAsianSide.home,
      handicap: 0.0,
    );

    expect(value?.settlement, SmartBetAsianSettlement.push);
    expect(value?.profitUnitsForDecimalOdd(1.80), 0.0);
    expect(value?.returnedUnitsForDecimalOdd(1.80), 1.0);
  });
}
