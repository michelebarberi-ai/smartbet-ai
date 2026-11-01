import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_market_settlement.dart';
import 'package:smartbet_ai_new/services/smartbet_extra_markets_odds_parser.dart';
import 'package:smartbet_ai_new/services/smartbet_market_probability_service.dart';
import 'package:smartbet_ai_new/services/smartbet_multi_market_selection_service.dart';

AnalysisResult analysis() => const AnalysisResult(
  smartScore: 72,
  homeProbability: 48,
  drawProbability: 26,
  awayProbability: 26,
  expectedHomeGoals: 1.6,
  expectedAwayGoals: 1.2,
  prediction: '1X',
  valueBet: '',
  risk: 'medio',
  explanation: '',
);

void main() {
  test('nuove famiglie sono disponibili e valgono nel massimo tre', () {
    expect(
      SmartBetMultiMarketSelectionService.selectable,
      containsAll(['MULTIGOL', 'COMBO AVANZATE', 'HANDICAP EUROPEO']),
    );
    expect(
      () => SmartBetMultiMarketSelectionService.searchProbability(
        analysis: analysis(),
        families: ['MULTIGOL', 'COMBO AVANZATE', 'OVER', 'UNDER'],
      ),
      throwsArgumentError,
    );
  });

  test('probabilita multigol e combo non si ricavano dalle quote', () {
    final a = analysis();
    final p14 = SmartBetMarketProbabilityService.probabilityFor(
      a,
      'MULTIGOL 1-4',
    );
    final p24 = SmartBetMarketProbabilityService.probabilityFor(
      a,
      'MULTIGOL 2-4',
    );
    expect(p14, greaterThan(p24));
    final combo = SmartBetMarketProbabilityService.probabilityFor(
      a,
      '1X + O2.5',
    );
    expect(combo, inInclusiveRange(1, 99));
    expect(SmartBetMarketProbabilityService.probabilityFor(a, '2 + U2.5'), 0);
  });

  test('le nuove combo si risolvono con punteggio full time', () {
    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: '1X + O2.5',
        homeGoals: 2,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.correct,
    );
    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: '1 + U3.5',
        homeGoals: 0,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.wrong,
    );
    expect(
      SmartBetAnalysisMarketSettlement.evaluate(
        market: 'MULTIGOL 2-5',
        homeGoals: 3,
        awayGoals: 1,
      ),
      SmartBetAnalysisSettlement.correct,
    );
  });

  test('non inventa quote per mercati senza bookmaker', () {
    final odds = FixtureMarketOdds(
      fixtureId: 101,
      matchWinner: null,
      bestByOutcome: {},
      bookmakerCount: 0,
    );
    expect(
      SmartBetMultiMarketSelectionService.bestQuoted(
        analysis: analysis(),
        odds: odds,
        families: ['MULTIGOL', 'COMBO AVANZATE'],
      ),
      isNull,
    );
  });

  test('quote multigol: nomi espliciti e range consentiti', () {
    expect(
      SmartBetExtraMarketsOddsParser.outcomeFor(
        betName: 'Multi Goals',
        value: '2-5',
      ),
      'MULTIGOL 2-5',
    );
    expect(
      SmartBetExtraMarketsOddsParser.outcomeFor(
        betName: 'Total Goals Range',
        value: 'MultiGol 1-4',
      ),
      'MULTIGOL 1-4',
    );
    expect(
      SmartBetExtraMarketsOddsParser.outcomeFor(
        betName: 'Multi Goals 2-4',
        value: 'Yes',
      ),
      'MULTIGOL 2-4',
    );
    expect(
      SmartBetExtraMarketsOddsParser.outcomeFor(
        betName: 'Double Chance and Total Goals',
        value: '1X & Over 2.5',
      ),
      '1X + O2.5',
    );
    expect(
      SmartBetExtraMarketsOddsParser.outcomeFor(
        betName: 'First Half Goals Over/Under',
        value: '1X & Over 2.5',
      ),
      isNull,
    );
    expect(
      SmartBetExtraMarketsOddsParser.outcomeFor(
        betName: 'Goals Over/Under',
        value: '2-5',
      ),
      isNull,
    );
    expect(
      SmartBetExtraMarketsOddsParser.outcomeFor(
        betName: 'Multi Goals',
        value: '5-7',
      ),
      isNull,
    );
  });

  test('scelta dal modello: quota minima usata solo dopo ranking', () {
    final odds = FixtureMarketOdds(
      fixtureId: 101,
      matchWinner: null,
      bookmakerCount: 1,
      bestByOutcome: {
        'MULTIGOL 1-4': const BestOdd(
          outcome: 'MULTIGOL 1-4',
          odd: 1.50,
          bookmakerId: 1,
          bookmakerName: 'Test',
        ),
        'MULTIGOL 2-4': const BestOdd(
          outcome: 'MULTIGOL 2-4',
          odd: 2.70,
          bookmakerId: 1,
          bookmakerName: 'Test',
        ),
      },
    );
    final pick = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: analysis(),
      odds: odds,
      families: ['MULTIGOL'],
    );
    expect(pick, isNotNull);
    expect(pick!.market, 'MULTIGOL 1-4');
  });
}
