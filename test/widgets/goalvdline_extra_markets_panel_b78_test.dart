import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_extra_markets_panel.dart';

void main() {
  testWidgets('B79: Altri groups four read-only market families',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineExtraMarketsPanel(),
        ),
      ),
    ));
    expect(find.text('Altri'), findsOneWidget);
    await tester.tap(find.text('Altri'));
    await tester.pumpAndSettle();

    expect(find.text('Primo tempo · 1 / X / 2'), findsOneWidget);
    expect(find.text('Secondo tempo · 1 / X / 2'), findsOneWidget);
    expect(find.text('Corner · totale partita'), findsOneWidget);
    expect(find.text('Tiri in porta · totale partita'), findsOneWidget);
    expect(find.textContaining('non selezionarli per le schedine'),
        findsOneWidget);

    await tester.tap(find.text('Primo tempo · 1 / X / 2'));
    await tester.pumpAndSettle();
    expect(find.text('1T 1'), findsOneWidget);
    expect(find.text('Dati N/D'), findsWidgets);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('B79: Altri labels experimental probabilities correctly',
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
    await tester.tap(find.text('Altri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primo tempo · 1 / X / 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('45%'), findsOneWidget);
    expect(find.textContaining('Non calibrato'), findsOneWidget);

    await tester.ensureVisible(find.text('Tiri in porta · totale partita'));
    await tester.tap(find.text('Tiri in porta · totale partita'));
    await tester.pumpAndSettle();
    expect(find.text('TIRI PORTA OVER 4.5'), findsOneWidget);
    expect(find.text('TIRI PORTA UNDER 9.5'), findsOneWidget);
  });
}
