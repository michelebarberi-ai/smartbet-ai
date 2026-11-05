import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_policy_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_projection_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_store.dart';

SmartBetSimulationShadowSnapshot _snapshot({DateTime? captured}) =>
    SmartBetSimulationShadowSnapshot(
      fixtureId: 15,
      engine: 'SMARTBET_CONTEXT',
      matchDate: DateTime.utc(2026, 12, 4, 20),
      capturedAt: captured ?? DateTime.utc(2026, 12, 3, 12),
      modelVersion: 'p21v-contextual-poisson-v1',
      expectedHomeGoals: 1.5,
      expectedAwayGoals: 1.1,
      dataQuality: 0.8,
      originalProbabilities: const {'X': 0.25, '1': 0.50},
      simulatedProbabilities: const {'X': 0.40, '1': 0.44},
      unsupportedMarkets: const [],
    );

SmartBetSimulationShadowPolicy _policy({DateTime? promotedAt}) =>
    SmartBetSimulationShadowPolicy(
      engine: 'SMARTBET_CONTEXT',
      market: 'X',
      modelVersion: 'p21v-contextual-poisson-v1',
      simulationWeight: 0.25,
      validationImprovement: 0.005,
      trainingCases: 80,
      validationCases: 60,
      promotedAt: promotedAt ?? DateTime.utc(2026, 12, 2),
    );

void main() {
  const service = SmartBetSimulationShadowProjectionService();
  final now = DateTime.utc(2026, 12, 3, 18);

  test('P21V: applica peso soltanto in anteprima SHADOW futura', () {
    final snapshot = _snapshot();
    final projected = service.preview(
      snapshots: [snapshot],
      policies: [_policy()],
      asOf: now,
    );
    expect(projected, hasLength(1));
    expect(projected.single.market, 'X');
    expect(projected.single.projected, closeTo(0.2875, 1e-10));
    expect(snapshot.originalProbabilities['X'], 0.25);
  });

  test('P21V: non applica retroattivamente policy approvata dopo snapshot', () {
    final projected = service.preview(
      snapshots: [_snapshot()],
      policies: [_policy(promotedAt: DateTime.utc(2026, 12, 3, 14))],
      asOf: now,
    );
    expect(projected, isEmpty);
  });

  test('P21V: non mostra partite gia iniziate', () {
    final projected = service.preview(
      snapshots: [_snapshot()],
      policies: [_policy()],
      asOf: DateTime.utc(2026, 12, 5),
    );
    expect(projected, isEmpty);
  });

  test('P21V: niente policy, niente proiezioni', () {
    expect(
      service.preview(snapshots: [_snapshot()], policies: const [], asOf: now),
      isEmpty,
    );
  });

  test('P21V: limite proiezioni rispettato', () {
    expect(
      service.preview(
        snapshots: [_snapshot()],
        policies: [_policy()],
        asOf: now,
        limit: 0,
      ),
      isEmpty,
    );
  });
}
