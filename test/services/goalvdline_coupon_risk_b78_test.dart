import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_coupon_risk_service.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_coupon_risk_notice.dart';

GoalVdLineCouponRiskSelection selection(
  int fixture, {
  double? probability = 90,
  double? odd = 1.25,
}) => GoalVdLineCouponRiskSelection(
  fixtureId: fixture.toString(),
  probabilityPercent: probability,
  realOdd: odd,
);

void main() {
  const service = GoalVdLineCouponRiskService();

  test('B78: 15 selections each 90% do not imply a safe 15-fold coupon',
      () {
    final report = service.evaluate([
      for (var i = 0; i < 15; i++) selection(i),
    ]);
    expect(report.events, 15);
    expect(report.distinctFixtures, 15);
    expect(report.veryLongMultiple, isTrue);
    expect(report.requiresAttention, isTrue);
    expect(report.independenceScenarioPercent,
        closeTo(20.589, 0.01));
  });

  test('B78: odds cannot alter hypothetical sporting scenario', () {
    final a = service.evaluate([
      selection(1, probability: 80, odd: 1.25),
      selection(2, probability: 75, odd: 1.75),
    ]);
    final b = service.evaluate([
      selection(1, probability: 80, odd: 10),
      selection(2, probability: 75, odd: 1.02),
    ]);
    expect(a.independenceScenarioPercent,
        b.independenceScenarioPercent);
    expect(a.independenceScenarioPercent, closeTo(60, 1e-10));
    expect(a.lowOrUnknownOdds, 0);
    expect(b.lowOrUnknownOdds, 1);
  });

  test('B78: invalid or missing probabilities do not invent a win rate',
      () {
    final report = service.evaluate([
      selection(1, probability: null),
      selection(2, probability: 101),
      selection(3, probability: double.nan),
      selection(4, probability: 95),
    ]);
    expect(report.missingOrInvalidProbabilities, 3);
    expect(report.independenceScenarioPercent, isNull);
  });

  test('B78: repeated fixtures forbid independence product', () {
    final report = service.evaluate([
      selection(1, probability: 90),
      selection(1, probability: 90),
      selection(2, probability: 90),
    ]);
    expect(report.repeatedFixtureSelections, 1);
    expect(report.hasRepeatRisk, isTrue);
    expect(report.independenceScenarioPercent, isNull);
  });

  test('B78: a normal short coupon is not called safe or guaranteed',
      () {
    final report = service.evaluate([
      selection(1, probability: 95), selection(2, probability: 95),
    ]);
    expect(report.longMultiple, isFalse);
    expect(report.veryLongMultiple, isFalse);
    expect(report.independenceScenarioPercent, closeTo(90.25, 1e-6));
    expect(report.requiresAttention, isFalse);
  });

  testWidgets('B78: warns 15-fold even if each pick looks easy',
      (tester) async {
    final report = service.evaluate([
      for (var i = 0; i < 15; i++) selection(i),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineCouponRiskNotice(report: report),
        ),
      ),
    ));
    expect(find.byKey(const Key('b78-coupon-risk-notice')), findsOneWidget);
    expect(find.textContaining('Multipla molto lunga'), findsOneWidget);
    expect(find.textContaining('20.6%'), findsOneWidget);
    expect(find.textContaining('Non è una probabilità reale'), findsOneWidget);
  });
}
