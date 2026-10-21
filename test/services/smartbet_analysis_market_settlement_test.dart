import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/smartbet_analysis_market_settlement.dart';

void main() {
  SmartBetAnalysisSettlement settle(String market, int home, int away) {
    return SmartBetAnalysisMarketSettlement.evaluate(
      market: market,
      homeGoals: home,
      awayGoals: away,
    );
  }

  group('1X2 e doppia chance', () {
    test('1 X 2', () {
      expect(settle('1', 2, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('X', 1, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('2', 0, 3), SmartBetAnalysisSettlement.correct);

      expect(settle('1', 0, 1), SmartBetAnalysisSettlement.wrong);
    });

    test('1X X2 12', () {
      expect(settle('1X', 1, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('X2', 0, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('12', 2, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('12', 2, 2), SmartBetAnalysisSettlement.wrong);
    });
  });

  group('Over Under', () {
    test('linee 1.5 2.5 3.5 4.5', () {
      expect(settle('OVER 2.5', 2, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('UNDER 2.5', 1, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('OVER 3.5', 2, 2), SmartBetAnalysisSettlement.correct);

      expect(settle('UNDER 3.5', 2, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('OVER 4.5', 3, 2), SmartBetAnalysisSettlement.correct);

      expect(settle('UNDER 4.5', 2, 2), SmartBetAnalysisSettlement.correct);
    });
  });

  group('Goal e team goals', () {
    test('Goal / No Goal', () {
      expect(settle('GOAL', 2, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('NO GOAL', 2, 0), SmartBetAnalysisSettlement.correct);

      expect(settle('GOAL', 2, 0), SmartBetAnalysisSettlement.wrong);
    });

    test('Casa / Ospite segna', () {
      expect(settle('CASA SEGNA', 1, 0), SmartBetAnalysisSettlement.correct);

      expect(settle('OSPITE SEGNA', 0, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('CASA 2+ GOL', 2, 0), SmartBetAnalysisSettlement.correct);

      expect(settle('OSPITE 3+ GOL', 1, 3), SmartBetAnalysisSettlement.correct);
    });

    test('Segna prima non viene falsamente valutato', () {
      expect(
        settle('CASA SEGNA PRIMA', 3, 1),
        SmartBetAnalysisSettlement.unsupported,
      );

      expect(
        settle('OSPITE SEGNA PRIMA', 1, 3),
        SmartBetAnalysisSettlement.unsupported,
      );
    });
  });

  group('Multigol', () {
    test('range inclusivo', () {
      expect(settle('MULTIGOL 1-4', 2, 2), SmartBetAnalysisSettlement.correct);

      expect(settle('MULTIGOL 2-4', 1, 0), SmartBetAnalysisSettlement.wrong);

      expect(settle('MULTIGOL 2-5', 3, 2), SmartBetAnalysisSettlement.correct);

      expect(settle('MULTIGOL 3-5', 3, 3), SmartBetAnalysisSettlement.wrong);
    });
  });

  group('Combo Chance', () {
    test('combo con shorthand O', () {
      expect(settle('1X + O1.5', 2, 1), SmartBetAnalysisSettlement.correct);

      expect(settle('1X + O1.5', 0, 2), SmartBetAnalysisSettlement.wrong);
    });

    test('combo con nome Over completo', () {
      expect(settle('X2 + OVER 1.5', 1, 2), SmartBetAnalysisSettlement.correct);
    });
  });

  test('mercato sconosciuto resta unsupported', () {
    expect(
      settle('MERCATO FUTURO', 2, 1),
      SmartBetAnalysisSettlement.unsupported,
    );
  });
}
