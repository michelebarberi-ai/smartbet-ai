import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_asian_handicap_settlement_service.dart';

void main() {
  SmartBetAsianSettlement home(double line, {int h = 2, int a = 1}) {
    return SmartBetAsianHandicapSettlementService.evaluate(
      homeGoals: h,
      awayGoals: a,
      side: SmartBetAsianSide.home,
      handicap: line,
    );
  }

  SmartBetAsianSettlement away(double line, {int h = 2, int a = 1}) {
    return SmartBetAsianHandicapSettlementService.evaluate(
      homeGoals: h,
      awayGoals: a,
      side: SmartBetAsianSide.away,
      handicap: line,
    );
  }

  test('Casa -0.5: vittoria', () {
    expect(home(-0.5), SmartBetAsianSettlement.win);
  });

  test('Casa -0.75: mezza vittoria', () {
    expect(home(-0.75), SmartBetAsianSettlement.halfWin);
  });

  test('Casa -1: rimborso', () {
    expect(home(-1), SmartBetAsianSettlement.push);
  });

  test('Casa -1.25: mezza perdita', () {
    expect(home(-1.25), SmartBetAsianSettlement.halfLoss);
  });

  test('Casa -1.5: perdita', () {
    expect(home(-1.5), SmartBetAsianSettlement.loss);
  });

  test('Ospite +1: rimborso', () {
    expect(away(1), SmartBetAsianSettlement.push);
  });

  test('Ospite +1.25: mezza vittoria', () {
    expect(away(1.25), SmartBetAsianSettlement.halfWin);
  });

  test('Draw No Bet casa: pareggio rimborsato', () {
    expect(
      SmartBetAsianHandicapSettlementService.drawNoBet(
        homeGoals: 1,
        awayGoals: 1,
        side: SmartBetAsianSide.home,
      ),
      SmartBetAsianSettlement.push,
    );
  });

  test('Draw No Bet ospite: vittoria ospite', () {
    expect(
      SmartBetAsianHandicapSettlementService.drawNoBet(
        homeGoals: 1,
        awayGoals: 2,
        side: SmartBetAsianSide.away,
      ),
      SmartBetAsianSettlement.win,
    );
  });

  test('Draw No Bet casa: sconfitta', () {
    expect(
      SmartBetAsianHandicapSettlementService.drawNoBet(
        homeGoals: 1,
        awayGoals: 2,
        side: SmartBetAsianSide.home,
      ),
      SmartBetAsianSettlement.loss,
    );
  });

  test('Rifiuta linee non multiple di 0.25', () {
    expect(home(-0.3), SmartBetAsianSettlement.unsupported);
  });

  test('Rifiuta risultati negativi', () {
    expect(home(-1, h: -1), SmartBetAsianSettlement.unsupported);
  });

  test('Rifiuta handicap fuori intervallo', () {
    expect(home(-6), SmartBetAsianSettlement.unsupported);
  });

  test('Una linea positiva favorisce la casa', () {
    expect(home(1.5, h: 0, a: 1), SmartBetAsianSettlement.win);
  });

  test('Handicap zero equivale a Draw No Bet', () {
    final regular = home(0, h: 2, a: 2);

    final dnb = SmartBetAsianHandicapSettlementService.drawNoBet(
      homeGoals: 2,
      awayGoals: 2,
      side: SmartBetAsianSide.home,
    );

    expect(regular, SmartBetAsianSettlement.push);
    expect(dnb, regular);
  });
}
