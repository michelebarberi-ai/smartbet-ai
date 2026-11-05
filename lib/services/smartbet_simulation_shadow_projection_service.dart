import 'smartbet_simulation_shadow_policy_service.dart';
import 'smartbet_simulation_shadow_store.dart';

/// Anteprima delle sole previsioni SHADOW effettuabili nel futuro.
/// Le policy devono essere state promosse PRIMA dello snapshot, altrimenti
/// il calcolo retroattivo introdurrebbe look-ahead bias.
class SmartBetSimulationShadowProjection {
  final int fixtureId;
  final String engine;
  final String market;
  final DateTime kickoff;
  final double original;
  final double simulated;
  final double projected;

  const SmartBetSimulationShadowProjection({
    required this.fixtureId,
    required this.engine,
    required this.market,
    required this.kickoff,
    required this.original,
    required this.simulated,
    required this.projected,
  });
}

class SmartBetSimulationShadowProjectionService {
  const SmartBetSimulationShadowProjectionService();

  /// Nessuna persistenza, nessun aggiornamento delle probabilita ufficiali.
  List<SmartBetSimulationShadowProjection> preview({
    required Iterable<SmartBetSimulationShadowSnapshot> snapshots,
    required Iterable<SmartBetSimulationShadowPolicy> policies,
    required DateTime asOf,
    int limit = 5,
  }) {
    if (limit <= 0) return const [];
    final policyMap = <String, SmartBetSimulationShadowPolicy>{
      for (final policy in policies) policy.key: policy,
    };
    final now = asOf.toUtc();
    final candidates =
        snapshots
            .where(
              (s) =>
                  s.matchDate.toUtc().isAfter(now) &&
                  s.capturedAt.toUtc().isBefore(s.matchDate.toUtc()),
            )
            .toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final result = <SmartBetSimulationShadowProjection>[];
    for (final snapshot in candidates) {
      final engine = snapshot.engine.trim().toUpperCase();
      for (final entry in snapshot.originalProbabilities.entries) {
        final market = entry.key.trim().toUpperCase();
        final policy = policyMap['$engine|$market|${snapshot.modelVersion}'];
        final simulated = snapshot.simulatedProbabilities[entry.key];
        if (policy == null ||
            simulated == null ||
            !policy.promotedAt.toUtc().isBefore(snapshot.capturedAt.toUtc())) {
          continue;
        }
        final original = entry.value;
        if (!original.isFinite ||
            !simulated.isFinite ||
            original < 0 ||
            original > 1 ||
            simulated < 0 ||
            simulated > 1) {
          continue;
        }
        final weight = policy.simulationWeight;
        result.add(
          SmartBetSimulationShadowProjection(
            fixtureId: snapshot.fixtureId,
            engine: engine,
            market: market,
            kickoff: snapshot.matchDate,
            original: original,
            simulated: simulated,
            projected: (original * (1 - weight) + simulated * weight)
                .clamp(0.0, 1.0)
                .toDouble(),
          ),
        );
        if (result.length >= limit) return List.unmodifiable(result);
      }
    }
    return List.unmodifiable(result);
  }
}
