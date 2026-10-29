import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_european_handicap_candidate_service.dart';
import 'package:smartbet_ai_new/services/smartbet_european_handicap_odds_parser.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_market_settlement.dart';

void main() {
  FixtureMarketOdds makeOdds(Map<String, double> rawValues, {int betId = 9}) {
    final best = <String, BestOdd>{};

    for (final entry in rawValues.entries) {
      final market = SmartBetEuropeanHandicapOddsParser.outcomeFor(
        betId: betId,
        value: entry.key,
      );

      if (market == null) continue;

      best[market] = BestOdd(
        outcome: market,
        odd: entry.value,
        bookmakerId: 1,
        bookmakerName: 'Bookmaker test',
      );
    }

    return FixtureMarketOdds(
      fixtureId: 1492439,
      matchWinner: null,
      bestByOutcome: best,
      bookmakerCount: 1,
    );
  }

  List<({String market, int probability})> candidates(FixtureMarketOdds odds) {
    return SmartBetEuropeanHandicapCandidateService.candidates(
      expectedHomeGoals: 1.7,
      expectedAwayGoals: 1.1,
      quotedOutcomes: odds.bestByOutcome.keys,
    );
  }

  test('P17A5: quote, probabilita ed esito sono coerenti', () {
    final odds = makeOdds({'Home -1': 10.00, 'Draw -1': 6.00, 'Away -1': 1.22});

    final selections = candidates(odds);

    expect(selections.length, 3);

    final draw = selections.singleWhere(
      (item) => item.market == 'HCP EURO CASA -1 X',
    );

    expect(draw.probability, inInclusiveRange(1, 99));
    expect(odds.oddFor(draw.market)?.odd, 6.00);

    final total = selections.fold<int>(
      0,
      (sum, item) => sum + item.probability,
    );

    expect(total, inInclusiveRange(99, 101));

    final settlement = SmartBetAnalysisMarketSettlement.evaluate(
      market: draw.market,
      homeGoals: 2,
      awayGoals: 1,
    );

    expect(settlement, SmartBetAnalysisSettlement.correct);
  });

  test('P17A5: senza quote non genera Handicap', () {
    final odds = makeOdds({});

    expect(odds.bestByOutcome, isEmpty);
    expect(candidates(odds), isEmpty);
  });

  test('P17A5: non confonde Handicap asiatico', () {
    final odds = makeOdds({
      'Home -1': 7.00,
      'Away -1': 1.10,
      'Home -0.75': 5.50,
    }, betId: 4);

    expect(odds.bestByOutcome, isEmpty);
    expect(candidates(odds), isEmpty);
  });

  test('P17A5: le linee Handicap rimangono distinte', () {
    final odds = makeOdds({'Draw -1': 6.00, 'Draw +1': 3.75});

    final selections = candidates(odds);

    expect(selections.length, 2);

    expect(odds.oddFor('HCP EURO CASA -1 X')?.odd, 6.00);

    expect(odds.oddFor('HCP EURO CASA 1 X')?.odd, 3.75);

    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: 'HCP EURO CASA -1 X',
        homeGoals: 2,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.correct,
    );

    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: 'HCP EURO CASA 1 X',
        homeGoals: 2,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.wrong,
    );
  });
}
