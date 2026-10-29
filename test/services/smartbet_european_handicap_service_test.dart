import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/smartbet_european_handicap_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_market_settlement.dart';

void main() {
  test('le probabilita europee sommano a uno', () {
    final p = SmartBetEuropeanHandicapService.evaluate(
      expectedHomeGoals: 1.6,
      expectedAwayGoals: 1.2,
      homeHandicap: -1,
    );

    expect(p.home + p.draw + p.away, closeTo(1, 1e-9));
    expect(p.home, inInclusiveRange(0.0, 1.0));
    expect(p.draw, inInclusiveRange(0.0, 1.0));
    expect(p.away, inInclusiveRange(0.0, 1.0));
  });

  test('con zero goal attesi e handicap zero e pareggio', () {
    final p = SmartBetEuropeanHandicapService.evaluate(
      expectedHomeGoals: 0,
      expectedAwayGoals: 0,
      homeHandicap: 0,
    );

    expect(p.draw, closeTo(1, 1e-9));
  });

  test('handicap negativo sfavorisce la casa', () {
    final base = SmartBetEuropeanHandicapService.evaluate(
      expectedHomeGoals: 1.6,
      expectedAwayGoals: 1.2,
      homeHandicap: 0,
    );

    final minusOne = SmartBetEuropeanHandicapService.evaluate(
      expectedHomeGoals: 1.6,
      expectedAwayGoals: 1.2,
      homeHandicap: -1,
    );

    expect(minusOne.home, lessThan(base.home));
    expect(minusOne.away, greaterThan(base.away));
  });

  test('handicap positivo favorisce la casa', () {
    final base = SmartBetEuropeanHandicapService.evaluate(
      expectedHomeGoals: 1.6,
      expectedAwayGoals: 1.2,
      homeHandicap: 0,
    );

    final plusOne = SmartBetEuropeanHandicapService.evaluate(
      expectedHomeGoals: 1.6,
      expectedAwayGoals: 1.2,
      homeHandicap: 1,
    );

    expect(plusOne.home, greaterThan(base.home));
  });

  test('rifiuta parametri non validi', () {
    expect(
      () => SmartBetEuropeanHandicapService.evaluate(
        expectedHomeGoals: double.nan,
        expectedAwayGoals: 1,
        homeHandicap: 0,
      ),
      throwsArgumentError,
    );
  });

  test('risultato 2-1 con handicap -1 produce X', () {
    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: 'HCP EURO CASA -1 X',
        homeGoals: 2,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.correct,
    );
  });

  test('risultato 2-1 con handicap -1 non produce 1', () {
    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: 'HCP EURO CASA -1 1',
        homeGoals: 2,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.wrong,
    );
  });

  test('handicap fuori limite non viene verificato', () {
    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: 'HCP EURO CASA -99 1',
        homeGoals: 2,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.unsupported,
    );
  });
}
