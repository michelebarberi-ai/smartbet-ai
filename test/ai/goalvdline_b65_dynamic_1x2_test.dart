import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/ai/statistics_engine.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/smartbet_multi_market_selection_service.dart';

void main() {
  Map<String, int> estimate(double home, double away) =>
      StatisticsEngine.probabilitiesFromExpectedGoals(
        expectedHomeGoals: home,
        expectedAwayGoals: away,
      );

  test('B65: le probabilità 1X2 variano con gli xG senza fasce fisse', () {
    final clearAway = estimate(0.55, 2.4);
    final balancedAway = estimate(1.2, 1.8);
    final slightlyHome = estimate(1.6, 1.25);

    for (final probabilities in [clearAway, balancedAway, slightlyHome]) {
      expect(probabilities.values.reduce((a, b) => a + b), 100);
      expect(probabilities.values.every((p) => p >= 0 && p <= 100), isTrue);
    }

    final strongX2 = clearAway['draw']! + clearAway['away']!;
    final moderateX2 = balancedAway['draw']! + balancedAway['away']!;
    final homeX2 = slightlyHome['draw']! + slightlyHome['away']!;

    expect(strongX2, greaterThan(moderateX2));
    expect(moderateX2, greaterThan(homeX2));
    expect(strongX2, isNot(moderateX2));
    expect(moderateX2, isNot(homeX2));
    expect(clearAway['away']!, greaterThan(clearAway['home']!));
  });

  test('B65: fixture con stessi xG produce stima 1X2 deterministica', () {
    expect(estimate(1.4, 1.7), estimate(1.4, 1.7));
    final balanced = estimate(1.5, 1.5);
    expect((balanced['home']! - balanced['away']!).abs(), lessThanOrEqualTo(1));
  });

  test('B65: xG assenti non generano probabilità artificiali', () {
    expect(estimate(0, 0), {'home': 0, 'draw': 0, 'away': 0});
    expect(estimate(double.nan, 1.6), {'home': 0, 'draw': 0, 'away': 0});
  });

  test('B65: il ranking 1+X2 conserva le stime differenti', () {
    AnalysisResult analysis(double home, double away) {
      final p = estimate(home, away);
      return AnalysisResult(
        smartScore: 75,
        homeProbability: p['home']!,
        drawProbability: p['draw']!,
        awayProbability: p['away']!,
        prediction: '2',
        valueBet: '',
        risk: 'MEDIO',
        explanation: 'stima sportiva',
      );
    }

    final a = SmartBetMultiMarketSelectionService.rankedSportsMarkets(
      analysis: analysis(0.55, 2.4), families: ['1', 'X2'],
    ).first;
    final b = SmartBetMultiMarketSelectionService.rankedSportsMarkets(
      analysis: analysis(1.2, 1.8), families: ['1', 'X2'],
    ).first;
    expect(a.market, 'X2');
    expect(b.market, 'X2');
    expect(a.probability, greaterThan(b.probability));
  });
}
