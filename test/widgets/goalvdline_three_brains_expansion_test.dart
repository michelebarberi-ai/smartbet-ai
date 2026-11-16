import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_three_brains_expansion.dart';

void main() {
  AnalysisResult smart({int score = 60, double home = 0.85,
      double away = 2.10}) => AnalysisResult(
    smartScore: score,
    homeProbability: 16,
    drawProbability: 21,
    awayProbability: 63,
    prediction: score > 0 ? '2' : 'N/D',
    valueBet: 'N/D',
    risk: 'Medio',
    expectedHomeGoals: home,
    expectedAwayGoals: away,
    dataConfidence: 52,
  );

  testWidgets('B63: simulation details are collapsed until tapped',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: GoalVdLineThreeBrainsExpansion(
          fixtureId: 17,
          smartBet: smart(),
          dual: null,
          selectedMarket: '2',
          selectedProbability: 63,
        ),
      )),
    ));
    expect(find.text('Analisi sintetica dei 3 cervelli'), findsOneWidget);
    expect(find.text('Simulatore'), findsNothing);
    await tester.tap(find.text('Analisi sintetica dei 3 cervelli'));
    await tester.pumpAndSettle();
    expect(find.text('SmartBet AI'), findsOneWidget);
    expect(find.text('Simulatore'), findsOneWidget);
    expect(find.text('Poisson bivariata'), findsOneWidget);
    expect(find.text('UNDER 5.5'), findsOneWidget);
    expect(find.textContaining('quote non entrano'), findsOneWidget);
  });

  testWidgets('B63: no valid expected goals shows no fake prediction',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: GoalVdLineThreeBrainsExpansion(
          fixtureId: 18,
          smartBet: smart(score: 0, home: 0, away: 0),
          dual: null,
          selectedMarket: 'N/D',
        ),
      )),
    ));
    await tester.tap(find.text('Analisi sintetica dei 3 cervelli'));
    await tester.pumpAndSettle();
    expect(find.text('Dati sui gol attesi insufficienti'), findsOneWidget);
    expect(find.textContaining('Non inventiamo una simulazione'), findsOneWidget);
  });
}
