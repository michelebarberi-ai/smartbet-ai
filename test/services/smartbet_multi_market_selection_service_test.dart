import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_multi_market_selection_service.dart';

AnalysisResult analysis() => const AnalysisResult(
  smartScore: 78,
  homeProbability: 60,
  drawProbability: 25,
  awayProbability: 15,
  over15Probability: 85,
  under15Probability: 15,
  over25Probability: 59,
  under25Probability: 41,
  goalProbability: 72,
  noGoalProbability: 28,
  expectedHomeGoals: 1.8,
  expectedAwayGoals: 1.2,
  prediction: '1',
  valueBet: '',
  risk: 'MEDIO',
  explanation: 'Test',
);

FixtureMarketOdds quotes(Map<String, double> values) => FixtureMarketOdds(
  fixtureId: 100,
  matchWinner: null,
  bookmakerCount: 1,
  bestByOutcome: {
    for (final entry in values.entries)
      entry.key: BestOdd(
        outcome: entry.key,
        odd: entry.value,
        bookmakerId: 1,
        bookmakerName: 'Bookmaker Test',
      ),
  },
);

void main() {
  final a = analysis();

  test('P19C: selezione fra 3 famiglie e mercato migliore', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'OVER 1.5': 1.40, 'GOAL': 1.60, '1': 2.80}),
      families: ['OVER', 'GOAL', '1'],
    );
    expect(result!.market, 'OVER 1.5');
    expect(result.probability, 85);
    expect(result.options.map((e) => e.market), contains('GOAL'));
  });

  test('P19C: quota <1.25 usa alternativa sportiva', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'OVER 1.5': 1.24, 'GOAL': 1.40, '1': 2.80}),
      families: ['OVER', 'GOAL', '1'],
    );
    expect(result!.market, 'GOAL');
    expect(result.probability, 72);
  });

  test('P19C: quota elevata non influenza ranking', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'OVER 1.5': 1.25, 'GOAL': 15.00}),
      families: ['OVER', 'GOAL'],
    );
    expect(result!.market, 'OVER 1.5');
  });

  test('P19C: senza quota reale non inventa selezioni', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'OVER 1.5': 1.20, 'GOAL': 1.24}),
      families: ['OVER', 'GOAL'],
    );
    expect(result, isNull);
  });

  test('P19C: minimo 1.25 incluso', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'OVER 1.5': 1.25}),
      families: ['OVER', 'GOAL'],
    );
    expect(result!.odd, 1.25);
  });

  test('P19C: quarto mercato respinto', () {
    expect(
      () => SmartBetMultiMarketSelectionService.searchProbability(
        analysis: a,
        families: ['OVER', 'UNDER', 'GOAL', '1'],
      ),
      throwsArgumentError,
    );
  });

  test('P19C: Combo Chance resta esclusiva e non quotata', () {
    expect(
      () => SmartBetMultiMarketSelectionService.searchProbability(
        analysis: a,
        families: ['GOAL', 'COMBO CHANCE'],
      ),
      throwsArgumentError,
    );
  });

  test('P19C: preliminare sportivo ignora quote', () {
    expect(
      SmartBetMultiMarketSelectionService.searchProbability(
        analysis: a,
        families: ['GOAL', '1', 'OVER'],
      ),
      85,
    );
  });

  test('P19C: handicap europeo disponibile solo se quotato', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'HCP EURO CASA -3 2': 1.40}),
      families: ['HANDICAP EUROPEO', 'GOAL'],
    );
    expect(result!.market, 'HCP EURO CASA -3 2');
    expect(result.odd, 1.40);
  });

  test('P19C: mercato duplicato in più famiglie non raddoppiato', () {
    final result = SmartBetMultiMarketSelectionService.bestQuoted(
      analysis: a,
      odds: quotes({'CASA SEGNA': 1.40, 'CASA 2+ GOL': 1.50}),
      families: ['CASA SEGNA', '1'],
    );
    expect(result, isNotNull);
    expect(
      result!.options.map((e) => e.market).toSet().length,
      result.options.length,
    );
  });
}
