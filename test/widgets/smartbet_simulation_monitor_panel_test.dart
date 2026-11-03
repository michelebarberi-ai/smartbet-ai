import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_outcome_audit_service.dart';
import 'package:smartbet_ai_new/widgets/smartbet_simulation_monitor_panel.dart';

SmartBetSimulationOutcomeAuditReport report({
  int snapshots = 2,
  Map<String, SmartBetSimulationOutcomeMarketMetric>? metrics,
}) {
  return SmartBetSimulationOutcomeAuditReport(
    snapshotCount: snapshots,
    comparedSnapshots: snapshots == 0 ? 0 : 1,
    pendingSnapshots: snapshots == 0 ? 0 : 1,
    conflictingFixtures: 0,
    duplicateSnapshots: 0,
    invalidFixtureSnapshots: 0,
    unsupportedMarketPairs: 0,
    unmatchedMarketPairs: 0,
    metrics: metrics ?? const {},
  );
}

SmartBetSimulationOutcomeMarketMetric draw({double simulatedBrier = 0.36}) {
  return SmartBetSimulationOutcomeMarketMetric(
    engine: 'SMARTBET',
    market: 'X',
    sampleSize: 1,
    occurred: 1,
    meanOriginalProbability: 0.25,
    meanSimulatedProbability: 0.40,
    observedFrequency: 1,
    originalBrier: 0.5625,
    simulatedBrier: simulatedBrier,
  );
}

Future<void> expand(WidgetTester tester) async {
  await tester.tap(find.text('Simulatore • confronto P21E (SHADOW)'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('P21E: nessun audit all’apertura, solo al pulsante', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartBetSimulationMonitorPanel(
              loadReport: () async {
                calls++;
                return report(metrics: {'SMARTBET|X': draw()});
              },
            ),
          ),
        ),
      ),
    );
    expect(calls, 0);
    await expand(tester);
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('p21e_run_audit')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Brier originale: 0.5625'), findsOneWidget);
    expect(find.text('Brier simulato: 0.3600'), findsOneWidget);
    expect(
      find.text('Campioni verificati: 1 • Esiti positivi: 1'),
      findsOneWidget,
    );
  });

  testWidgets('P21E: dati mancanti mostrati senza numeri inventati', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartBetSimulationMonitorPanel(
              loadReport: () async => report(snapshots: 0),
            ),
          ),
        ),
      ),
    );
    await expand(tester);
    await tester.tap(find.byKey(const ValueKey('p21e_run_audit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('p21e_no_comparisons')), findsOneWidget);
    expect(find.text('Snapshot prepartita: 0'), findsOneWidget);
  });

  testWidgets('P21E: evita avvii duplicati durante elaborazione', (
    tester,
  ) async {
    final gate = Completer<SmartBetSimulationOutcomeAuditReport>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartBetSimulationMonitorPanel(
              loadReport: () {
                calls++;
                return gate.future;
              },
            ),
          ),
        ),
      ),
    );
    await expand(tester);
    await tester.tap(find.byKey(const ValueKey('p21e_run_audit')));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('p21e_run_audit')))
          .onPressed,
      isNull,
    );
    gate.complete(report());
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('P21E: il fallimento locale non avvia altre analisi', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartBetSimulationMonitorPanel(
              loadReport: () async {
                throw StateError('Storico non disponibile');
              },
            ),
          ),
        ),
      ),
    );
    await expand(tester);
    await tester.tap(find.byKey(const ValueKey('p21e_run_audit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('p21e_error')), findsOneWidget);
  });

  testWidgets('P21E: distingue Brier migliorativo e peggiorativo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartBetSimulationAuditReportView(
              report: report(
                metrics: {
                  'SMARTBET|X': draw(),
                  'DIEGO|OVER 2.5': SmartBetSimulationOutcomeMarketMetric(
                    engine: 'DIEGO',
                    market: 'OVER 2.5',
                    sampleSize: 1,
                    occurred: 0,
                    meanOriginalProbability: 0.2,
                    meanSimulatedProbability: 0.8,
                    observedFrequency: 0,
                    originalBrier: 0.04,
                    simulatedBrier: 0.64,
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Simulato migliore nel campione • Campione piccolo (<50)'),
      findsOneWidget,
    );
    expect(
      find.text('Originale migliore nel campione • Campione piccolo (<50)'),
      findsOneWidget,
    );
  });
}
