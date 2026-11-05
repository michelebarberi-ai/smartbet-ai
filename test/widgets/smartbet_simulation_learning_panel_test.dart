import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_learning_validation_service.dart';
import 'package:smartbet_ai_new/widgets/smartbet_simulation_learning_panel.dart';

SmartBetSimulationLearningMarketResult result(
  SmartBetSimulationLearningDecision decision,
) => SmartBetSimulationLearningMarketResult(
  engine: 'SMARTBET',
  market: 'X',
  modelVersion: 'P21A-v1',
  decision: decision,
  eligibleCases: 140,
  trainingCases: 80,
  validationCases: 60,
  lowQualityCases: 12,
  trainingDays: 20,
  validationDays: 15,
  candidateSimulationWeight: 0.5,
  trainingOriginalBrier: 0.22,
  trainingCandidateBrier: 0.21,
  validationOriginalBrier: 0.23,
  validationCandidateBrier: 0.20,
  firstValidationHalfImprovement: 0.02,
  secondValidationHalfImprovement: 0.04,
);

SmartBetSimulationLearningReport report({
  List<SmartBetSimulationLearningMarketResult> markets = const [],
}) => SmartBetSimulationLearningReport(
  totalSnapshots: markets.isEmpty ? 0 : 140,
  pendingSnapshots: 0,
  conflictingSnapshots: 0,
  invalidSnapshots: 0,
  duplicateSnapshots: 0,
  unmatchedPairs: 0,
  unsupportedPairs: 0,
  markets: markets,
);

Future<void> openSection(WidgetTester tester) async {
  await tester.tap(find.text('Apprendimento simulatore • P21H (SHADOW)'));
  await tester.pumpAndSettle();
}

Widget page(Future<SmartBetSimulationLearningReport> Function() onLoad) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SmartBetSimulationLearningPanel(loadReport: onLoad),
        ),
      ),
    );

void main() {
  testWidgets('P21H: nessuna elaborazione automatica', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      page(() async {
        count++;
        return report();
      }),
    );
    expect(count, 0);
    await openSection(tester);
    expect(count, 0);
    await tester.tap(find.byKey(const ValueKey('p21h_run_validation')));
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(find.byKey(const ValueKey('p21h_empty')), findsOneWidget);
  });

  testWidgets('P21H: il candidato resta esplicitamente non attivo', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        () async => report(
          markets: [result(SmartBetSimulationLearningDecision.trialCandidate)],
        ),
      ),
    );
    await openSection(tester);
    await tester.tap(find.byKey(const ValueKey('p21h_run_validation')));
    await tester.pumpAndSettle();
    expect(find.text('Candidati per ulteriori test: 1'), findsOneWidget);
    expect(
      find.text('Candidato a ulteriori prove (NON attivo)'),
      findsOneWidget,
    );
    expect(find.text('Peso sperimentale del simulatore: 50%'), findsOneWidget);
    expect(
      find.text('Miglioramento Brier validazione: 0.0300'),
      findsOneWidget,
    );
  });

  testWidgets('P21H: nessun miglioramento non viene approvato', (tester) async {
    await tester.pumpWidget(
      page(
        () async => report(
          markets: [
            result(SmartBetSimulationLearningDecision.validationFailed),
          ],
        ),
      ),
    );
    await openSection(tester);
    await tester.tap(find.byKey(const ValueKey('p21h_run_validation')));
    await tester.pumpAndSettle();
    expect(find.text('Candidati per ulteriori test: 0'), findsOneWidget);
    expect(find.text('Correzione respinta nella validazione'), findsOneWidget);
  });

  testWidgets('P21H: doppio avvio impedito', (tester) async {
    var count = 0;
    final gate = Completer<SmartBetSimulationLearningReport>();
    await tester.pumpWidget(
      page(() {
        count++;
        return gate.future;
      }),
    );
    await openSection(tester);
    await tester.tap(find.byKey(const ValueKey('p21h_run_validation')));
    await tester.pump();
    expect(count, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('p21h_run_validation')),
          )
          .onPressed,
      isNull,
    );
    gate.complete(report());
    await tester.pumpAndSettle();
    expect(count, 1);
  });

  testWidgets('P21H: errore locale comunicato senza rilancio', (tester) async {
    await tester.pumpWidget(
      page(() async {
        throw StateError('Dati locali indisponibili');
      }),
    );
    await openSection(tester);
    await tester.tap(find.byKey(const ValueKey('p21h_run_validation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('p21h_error')), findsOneWidget);
  });
}
