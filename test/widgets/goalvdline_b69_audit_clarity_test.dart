import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/diego_ai_service.dart';
import 'package:smartbet_ai_new/services/dual_engine_analysis_service.dart';
import 'package:smartbet_ai_new/widgets/dual_engine_summary.dart';

class _Diego implements DiegoAiAnalysis {
  @override
  double get homeProbability => 0.56;
  @override
  double get drawProbability => 0.25;
  @override
  double get awayProbability => 0.19;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

DualEngineAnalysis comparison() => DualEngineAnalysis(
  smartBet: const AnalysisResult(
    smartScore: 67,
    homeProbability: 65,
    drawProbability: 20,
    awayProbability: 15,
    sportsAuditStatus: 'NOT_RUN',
    prediction: '1',
    valueBet: '',
    risk: '',
    explanation: '',
  ),
  diego: _Diego(),
  comparison: const DualEngineComparison(
    status: DualEngineAgreement.unavailable,
    smartBetMarket: 'N/D',
    diegoMarket: 'CASA SEGNA',
    diegoProbability: 0.86,
    statisticalSmartBetMarket: '1',
    statisticalSmartBetProbability: 0.65,
  ),
);

Future<void> pumpComparison(WidgetTester tester,
    {String? localAudit}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DualEngineSummary(
          analysis: comparison(),
          localSelectionAuditStatus: localAudit,
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('B69: same-market 1X2 comparison avoids a fake 65 vs 86 agreement',
      (tester) async {
    await pumpComparison(tester);
    expect(find.textContaining('Confronto sullo stesso mercato 1'),
        findsOneWidget);
    expect(find.textContaining('GoalVdLine 65% · Diego 56%'),
        findsOneWidget);
    expect(find.textContaining('9 punti percentuali di differenza'),
        findsOneWidget);
    expect(find.textContaining('Il mercato Diego evidenziato sopra è diverso'),
        findsOneWidget);
    expect(find.text('AUDITOR SPORTIVO AVANZATO NON ESEGUITO'),
        findsOneWidget);
    expect(find.byKey(const Key('b69-local-audit-status')), findsNothing);
  });

  testWidgets('B69: local audit can pass while advanced audit is not run',
      (tester) async {
    await pumpComparison(tester, localAudit: 'CONFERMATA');
    expect(find.textContaining('AUDITOR LOCALE DELLA SELEZIONE: CONFERMATA'),
        findsOneWidget);
    expect(find.text('AUDITOR SPORTIVO AVANZATO NON ESEGUITO'),
        findsOneWidget);
  });

  testWidgets('B69: a local reserve is not presented as full verification',
      (tester) async {
    await pumpComparison(tester, localAudit: 'CON RISERVA');
    expect(find.textContaining('AUDITOR LOCALE DELLA SELEZIONE: CON RISERVA'),
        findsOneWidget);
    expect(find.text('AUDITOR SPORTIVO AVANZATO NON ESEGUITO'),
        findsOneWidget);
  });

  testWidgets('B69: arbitrary status never creates a fake audit badge',
      (tester) async {
    await pumpComparison(tester, localAudit: 'NON VERIFICATO');
    expect(find.byKey(const Key('b69-local-audit-status')), findsNothing);
  });
}
