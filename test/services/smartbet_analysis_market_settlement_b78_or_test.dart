import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_market_settlement.dart';
import 'package:smartbet_ai_new/services/smartbet_market_probability_service.dart';

SmartBetAnalysisSettlement check(String market, int home, int away) =>
    SmartBetAnalysisMarketSettlement.evaluate(
      market: market, homeGoals: home, awayGoals: away,
    );

void main() {
  test('B78: tutti i mercati OPPURE configurati seguono la logica OR',
      () {
    for (final market in SmartBetMarketProbabilityService.orMarkets) {
      final parts = market.split(' O ');
      expect(parts.length, 2, reason: market);
      for (var home = 0; home <= 6; home++) {
        for (var away = 0; away <= 6; away++) {
          final a = check(parts[0], home, away);
          final b = check(parts[1], home, away);
          final expected = a == SmartBetAnalysisSettlement.unsupported ||
                  b == SmartBetAnalysisSettlement.unsupported
              ? SmartBetAnalysisSettlement.unsupported
              : a == SmartBetAnalysisSettlement.correct ||
                      b == SmartBetAnalysisSettlement.correct
                  ? SmartBetAnalysisSettlement.correct
                  : SmartBetAnalysisSettlement.wrong;
          expect(check(market, home, away), expected,
              reason: '$market · $home-$away');
        }
      }
    }
  });

  test('B78: GOAL O UNDER e 2X O GOAL sono verificabili senza quote',
      () {
    expect(check('GOAL O UNDER 3.5', 3, 0),
        SmartBetAnalysisSettlement.correct);
    expect(check('GOAL O UNDER 3.5', 2, 2),
        SmartBetAnalysisSettlement.correct);
    expect(check('GOAL O UNDER 3.5', 5, 0),
        SmartBetAnalysisSettlement.wrong);
    expect(check('2X O GOAL', 0, 3),
        SmartBetAnalysisSettlement.correct);
    expect(check('2X O GOAL', 2, 2),
        SmartBetAnalysisSettlement.correct);
    expect(check('2X O GOAL', 2, 0),
        SmartBetAnalysisSettlement.wrong);
  });

  test('B78: OPPURE resta distinto dalla congiunzione +', () {
    expect(check('GOAL O OVER 2.5', 3, 0),
        SmartBetAnalysisSettlement.correct);
    expect(check('GOAL + O2.5', 3, 0),
        SmartBetAnalysisSettlement.wrong);
    expect(check('GOAL O OVER 2.5', 0, 0),
        SmartBetAnalysisSettlement.wrong);
  });

  test('B78: parte sconosciuta non produce una sconfitta inventata',
      () {
    expect(check('1X O MERCATO SCONOSCIUTO', 0, 1),
        SmartBetAnalysisSettlement.unsupported);
    expect(check('1X O MERCATO SCONOSCIUTO', 1, 1),
        SmartBetAnalysisSettlement.unsupported);
    expect(check('GOAL O UNDER', 2, 0),
        SmartBetAnalysisSettlement.unsupported);
    expect(check('GOAL O OVER 2.5 O X', 0, 0),
        SmartBetAnalysisSettlement.unsupported);
    expect(check('CASA SEGNA PRIMA O GOAL', 3, 0),
        SmartBetAnalysisSettlement.unsupported);
    expect(check('CASA SEGNA PRIMA O GOAL', 2, 1),
        SmartBetAnalysisSettlement.unsupported);
  });

  test('B78: normalizzazione e invalid score sono prudenti', () {
    expect(check(' goal   o   over 1.5 ', 1, 1),
        SmartBetAnalysisSettlement.correct);
    expect(check('GOAL O OVER 1.5', -1, 2),
        SmartBetAnalysisSettlement.unsupported);
    expect(check('NO GOAL', 2, 0),
        SmartBetAnalysisSettlement.correct);
    expect(check('UNDER 4.5', 4, 0),
        SmartBetAnalysisSettlement.correct);
  });
}
