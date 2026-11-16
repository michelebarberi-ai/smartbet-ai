import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_third_brain_service.dart';

class _FakeDiego implements DiegoAiAnalysis {
  @override
  final double expectedHomeGoals;
  @override
  final double expectedAwayGoals;
  @override
  final int dataConfidence;

  const _FakeDiego(this.expectedHomeGoals, this.expectedAwayGoals,
      this.dataConfidence);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

AnalysisResult _smart({
  int score = 0,
  double home = 0,
  double away = 0,
  int confidence = 0,
}) => AnalysisResult(
  smartScore: score,
  homeProbability: 0,
  drawProbability: 0,
  awayProbability: 0,
  prediction: 'N/D',
  valueBet: 'N/D',
  risk: 'N/D',
  expectedHomeGoals: home,
  expectedAwayGoals: away,
  dataConfidence: confidence,
);

void main() {
  const service = GoalVdLineThirdBrainService();

  test('B63: zero SmartBet and no Diego must never invent a simulation', () {
    expect(service.evaluate(smartBet: _smart()), isNull);
  });

  test('B63: Diego xG enable third simulation while SmartBet backend fails', () {
    final report = service.evaluate(
      smartBet: _smart(),
      diego: const _FakeDiego(0.98, 1.81, 45),
    );
    expect(report, isNotNull);
    expect(report!.inputSource, 'Diego AI');
    expect(report.sharesDiegoInputs, isTrue);
    expect(report.dataConfidence, 45);
    expect(report.homeExpectedGoals, 0.98);
    expect(report.awayExpectedGoals, 1.81);
    expect(report.markets.first.probability,
      greaterThan(report.markets.last.probability));
    expect(report.forMarket('UNDER 5.5'), isNotNull);
    expect(report.forMarket('X2')!.probability, greaterThan(0.5));
    expect(report.likelyScores, hasLength(3));
    for (final market in report.markets) {
      expect(market.probability, inInclusiveRange(0, 1));
      expect(market.lowerScenario, inInclusiveRange(0, 1));
      expect(market.upperScenario, inInclusiveRange(0, 1));
      expect(market.lowerScenario,
        lessThanOrEqualTo(market.probability + 1e-10));
      expect(market.upperScenario,
        greaterThanOrEqualTo(market.probability - 1e-10));
    }
  });

  test('B63: use valid independent SmartBet inputs when available', () {
    final report = service.evaluate(
      smartBet: _smart(score: 67, home: 0.75, away: 1.90, confidence: 72),
      diego: const _FakeDiego(0.98, 1.81, 45),
    );
    expect(report!.inputSource, 'SmartBet AI');
    expect(report.sharesDiegoInputs, isFalse);
    expect(report.homeExpectedGoals, 0.75);
    expect(report.dataConfidence, 72);
  });

  test('B63: high expected goals keep sensitivity within valid limits', () {
    final report = service.evaluate(
      smartBet: _smart(score: 90, home: 5.9, away: 5.9, confidence: 65),
    );
    expect(report, isNotNull);
    expect(report!.forMarket('UNDER 5.5'), isNotNull);
  });

  test('B63: invalid expected goals are rejected rather than estimated', () {
    final report = service.evaluate(
      smartBet: _smart(score: 90, home: double.nan, away: 2),
      diego: const _FakeDiego(0, 0, 45),
    );
    expect(report, isNull);
  });
}
