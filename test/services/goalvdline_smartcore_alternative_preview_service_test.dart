import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/goalvdline_smartcore_alternative_preview_service.dart';

AnalysisResult core({
  double home = 2.3,
  double away = 0.8,
  int dataConfidence = 0,
  int smartScore = 72,
}) => AnalysisResult(
  smartScore: smartScore,
  dataConfidence: dataConfidence,
  homeProbability: 72,
  drawProbability: 19,
  awayProbability: 9,
  over15Probability: 82,
  under15Probability: 18,
  over25Probability: 61,
  under25Probability: 39,
  goalProbability: 51,
  noGoalProbability: 49,
  expectedHomeGoals: home,
  expectedAwayGoals: away,
  prediction: '1',
  valueBet: 'N/D',
  risk: 'Medio',
  explanation: 'SmartCore originale',
);

void main() {
  const adapter = GoalVdLineSmartCoreAlternativePreviewService();

  test('SmartCore passa una sola analisi, senza quote o altri motori', () {
    final raw = core();
    final plan = adapter.build(raw)!;
    expect(plan.engineId, 'SmartCore');
    expect(plan.primaryMarket, '1');
    expect(plan.sportsAlternatives, isNotEmpty);
    expect(plan.quotedAlternatives, isEmpty);
    expect(plan.suggestedFallback, isNull);
    expect(raw.homeProbability, 72);
    expect(raw.prediction, '1');
    expect(raw.explanation, 'SmartCore originale');
  });

  test('Qualita dati non misurata non diventa SmartScore', () {
    final plan = adapter.build(core(dataConfidence: 0))!;
    expect(plan.dataQuality, 0);
    expect(plan.suggestedFallback, isNull);
    final withQuality = adapter.build(core(dataConfidence: 80))!;
    expect(withQuality.dataQuality, closeTo(0.8, 0.0001));
    expect(withQuality.quotedAlternatives, isEmpty);
  });

  test('Handicap 0-1 segno 1 implica vittoria di casa', () {
    final plan = adapter.build(core())!;
    final handicap = plan.sportsAlternatives.singleWhere(
      (item) => item.market == 'HCP EURO CASA -1 1',
    );
    expect(handicap.probability, lessThan(plan.primaryProbability));
    expect(handicap.probability, greaterThan(0));
  });

  test('Dati SmartCore non validi non introducono una stima', () {
    expect(adapter.build(core(home: 0)), isNull);
    expect(adapter.build(core(away: double.nan)), isNull);
    expect(adapter.build(core(smartScore: 0)), isNull);
  });
}
