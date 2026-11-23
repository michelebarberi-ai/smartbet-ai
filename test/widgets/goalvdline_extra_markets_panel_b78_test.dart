import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_extra_markets_panel.dart';

void main() {
  testWidgets('B78: new three families visible without API calls or estimates',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineExtraMarketsPanel(),
        ),
      ),
    ));
    expect(find.textContaining('Primo/secondo tempo'), findsOneWidget);
    await tester.tap(find.text('Mercati aggiuntivi · in osservazione'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Risultato 1° e 2° tempo'), findsOneWidget);
    expect(find.textContaining('Calci d’angolo'), findsOneWidget);
    expect(find.textContaining('Tiri in porta · totale'), findsOneWidget);
    expect(find.textContaining('Dati N/D'), findsWidgets);
  });

  testWidgets('B78: period model labelled simulation, not reliable coupon pick',
      (tester) async {
    final result = AnalysisResult(
      smartScore: 75, homeProbability: 52,
      drawProbability: 30, awayProbability: 18,
      expectedHomeGoals: 1.8, expectedAwayGoals: 1.0,
      prediction: '1', valueBet: '1', risk: 'medio',
      explanation: 'analisi sportiva',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineExtraMarketsPanel(analysis: result),
        ),
      ),
    ));
    await tester.tap(find.text('Mercati aggiuntivi · in osservazione'));
    await tester.pumpAndSettle();
    expect(find.textContaining('45% primo tempo e 55% secondo'), findsOneWidget);
    expect(find.textContaining('Non calibrato'), findsOneWidget);
    expect(find.textContaining('TIRI PORTA OVER 4.5'), findsOneWidget);
  });
}
