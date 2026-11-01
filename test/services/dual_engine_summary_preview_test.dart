import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/dual_engine_analysis_service.dart';
import 'package:smartbet_ai_new/widgets/dual_engine_summary.dart';

AnalysisResult sample({String audit = 'NOT_RUN'}) {
  return AnalysisResult(
    smartScore: 80,
    sportsAuditStatus: audit,
    homeProbability: 50,
    drawProbability: 25,
    awayProbability: 25,
    prediction: 'OVER 1.5',
    valueBet: '',
    risk: 'MEDIO',
    explanation: 'Test',
  );
}

Future<void> showComparison(
  WidgetTester tester,
  DualEngineComparison comparison, {
  String audit = 'NOT_RUN',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DualEngineSummary(
            analysis: DualEngineAnalysis(
              smartBet: sample(audit: audit),
              diego: null,
              comparison: comparison,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('P19B2D intestazione leggibile ed handicap tradotto', (
    tester,
  ) async {
    await showComparison(
      tester,
      const DualEngineComparison(
        status: DualEngineAgreement.unavailable,
        smartBetMarket: 'N/D',
        diegoMarket: 'UNDER 2.5',
        diegoProbability: 0.69,
        statisticalSmartBetMarket: 'HCP EURO CASA -2 2',
        statisticalSmartBetProbability: 0.87,
      ),
    );
    expect(find.text('RAFFRONTO TRA LE DUE IA'), findsOneWidget);
    expect(find.text('AUDITOR SPORTIVO NON ESEGUITO'), findsOneWidget);
    expect(find.text('HANDICAP EUROPEO · CASA -2 · ESITO 2'), findsOneWidget);
  });

  testWidgets('P19B2B mostra GoalVdLine quando la verifica non è eseguita', (
    tester,
  ) async {
    await showComparison(
      tester,
      const DualEngineComparison(
        status: DualEngineAgreement.unavailable,
        smartBetMarket: 'N/D',
        diegoMarket: 'OVER 1.5',
        diegoProbability: 0.84,
        statisticalSmartBetMarket: 'OVER 1.5',
        statisticalSmartBetProbability: 0.82,
      ),
    );

    expect(find.text('GOALVDLINE'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('OVER 1.5'), findsNWidgets(2));
    expect(find.textContaining('Stesso mercato statistico'), findsOneWidget);
    expect(find.text('AUDITOR SPORTIVO NON ESEGUITO'), findsOneWidget);
    expect(find.text('STESSO MERCATO'), findsNothing);
  });

  testWidgets('P19B2B indica mercati statistici differenti', (tester) async {
    await showComparison(
      tester,
      const DualEngineComparison(
        status: DualEngineAgreement.unavailable,
        smartBetMarket: 'N/D',
        diegoMarket: 'UNDER 2.5',
        diegoProbability: 0.69,
        statisticalSmartBetMarket: 'OVER 1.5',
        statisticalSmartBetProbability: 0.82,
      ),
    );

    expect(
      find.textContaining('Mercati statistici differenti'),
      findsOneWidget,
    );
    expect(find.text('82%'), findsOneWidget);
  });

  testWidgets('P19B2B senza preview non nasconde il veto', (tester) async {
    await showComparison(
      tester,
      const DualEngineComparison(
        status: DualEngineAgreement.unavailable,
        smartBetMarket: 'N/D',
        diegoMarket: 'GOAL',
        diegoProbability: 0.80,
      ),
      audit: 'STRONG_CONTRADICTION',
    );

    expect(find.text('SMARTBET'), findsOneWidget);
    expect(find.text('GOALVDLINE'), findsNothing);
    expect(find.text('CONFRONTO NON DISPONIBILE'), findsOneWidget);
  });

  testWidgets('P19B2B confronto verificato resta invariato', (tester) async {
    await showComparison(
      tester,
      const DualEngineComparison(
        status: DualEngineAgreement.agree,
        smartBetMarket: 'GOAL',
        smartBetProbability: 0.80,
        diegoMarket: 'GOAL',
        diegoProbability: 0.82,
      ),
      audit: 'CONFIRM',
    );

    expect(find.text('SMARTBET'), findsOneWidget);
    expect(find.text('STESSO MERCATO'), findsOneWidget);
    expect(find.text('GOALVDLINE'), findsNothing);
  });
}
