import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_high_handicap_alternative_service.dart';

AnalysisResult sample({List<String> blocked = const [], int score = 78}) =>
    AnalysisResult(
      smartScore: score,
      homeProbability: 68,
      drawProbability: 20,
      awayProbability: 12,
      expectedHomeGoals: 1.9,
      expectedAwayGoals: 0.8,
      sportsAuditBlockedMarkets: blocked,
      prediction: '1',
      valueBet: '',
      risk: 'MEDIO',
      explanation: 'Test alternativa HCP',
    );

BestOdd quote(String outcome, double odd, {String source = 'Bookmaker esempio'}) =>
    BestOdd(
      outcome: outcome,
      odd: odd,
      bookmakerId: 9,
      bookmakerName: source,
    );

FixtureMarketOdds feed(Map<String, BestOdd> quotes) =>
    FixtureMarketOdds(
      fixtureId: 77,
      matchWinner: null,
      bestByOutcome: quotes,
      bookmakerCount: 1,
    );

void main() {
  test('B62: solo handicap di ampiezza >= 3 attiva seconda scelta', () {
    expect(SmartBetHighHandicapAlternativeService.needsAlternative(
      'HCP EURO CASA -3 1'), isTrue);
    expect(SmartBetHighHandicapAlternativeService.needsAlternative(
      'HCP EURO CASA +3 X'), isTrue);
    expect(SmartBetHighHandicapAlternativeService.needsAlternative(
      'HCP EURO CASA -5 2'), isTrue);
    expect(SmartBetHighHandicapAlternativeService.needsAlternative(
      'HCP EURO CASA -2 1'), isFalse);
    expect(SmartBetHighHandicapAlternativeService.needsAlternative(
      'HCP ASIA OSPITE +3.5'), isTrue);
    expect(SmartBetHighHandicapAlternativeService.needsAlternative(
      'HCP ASIA CASA -2.5'), isFalse);
    expect(SmartBetHighHandicapAlternativeService.needsAlternative(
      'OVER 3.5'), isFalse);
  });

  test('B62: seconda scelta quotata, con bookmaker e percentuale distinta', () {
    final alternative = SmartBetHighHandicapAlternativeService.find(
      primaryMarket: 'HCP EURO CASA -3 1',
      analysis: sample(),
      odds: feed({
        '1X': quote('1X', 1.25, source:'Quota reale A'),
        '1': quote('1', 1.33, source:'Quota reale B'),
      }),
    );
    expect(alternative, isNotNull);
    expect(alternative!.market, '1X');
    expect(alternative.probability, 88);
    expect(alternative.odd, 1.25);
    expect(alternative.bookmaker, 'Quota reale A');
  });

  test('B62: un mercato di 12 percento non sostituisce l handicap', () {
    final alternative = SmartBetHighHandicapAlternativeService.find(
      primaryMarket: 'HCP EURO CASA +3 2',
      analysis: sample(),
      odds: feed({'2': quote('2', 11.0)}),
      minimumProbability: 65,
    );
    expect(alternative, isNull);
  });

  test('B62: quote non offerte e prezzi <= 1.20 non sono inventati', () {
    expect(SmartBetHighHandicapAlternativeService.find(
      primaryMarket: 'HCP EURO CASA -3 1',
      analysis: sample(),
      odds: null,
    ), isNull);
    expect(SmartBetHighHandicapAlternativeService.find(
      primaryMarket: 'HCP EURO CASA -3 1',
      analysis: sample(),
      odds: feed({'1X': quote('1X', 1.20)}),
    ), isNull);
  });

  test('B62: veto Auditor blocca alternativa anche se quotata', () {
    expect(SmartBetHighHandicapAlternativeService.find(
      primaryMarket: 'HCP EURO CASA -3 1',
      analysis: sample(blocked: ['1X', '1']),
      odds: feed({
        '1X': quote('1X', 1.27),
        '1': quote('1', 1.65),
      }),
    ), isNull);
  });

  test('B62: nessuna alternativa per handicap basso', () {
    expect(SmartBetHighHandicapAlternativeService.find(
      primaryMarket: 'HCP EURO CASA -2 1',
      analysis: sample(),
      odds: feed({'1X': quote('1X', 1.25)}),
    ), isNull);
  });
}
