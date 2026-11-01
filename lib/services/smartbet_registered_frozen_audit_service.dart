import 'smartbet_frozen_model_registration_store.dart';
import 'smartbet_frozen_snapshot_audit_service.dart';
import 'smartbet_shadow_outcome_service.dart';

enum SmartBetRegisteredAuditStatus {
  missingRegistration,
  invalidChronology,
  evaluated,
}

class SmartBetRegisteredAuditResult {
  final SmartBetRegisteredAuditStatus status;
  final String modelId;
  final int excludedBeforeRegistration;
  final SmartBetFrozenSnapshotAuditReport? audit;

  const SmartBetRegisteredAuditResult({
    required this.status,
    required this.modelId,
    required this.excludedBeforeRegistration,
    required this.audit,
  });

  bool get evaluated => status == SmartBetRegisteredAuditStatus.evaluated;
}

/// Audit locale di un modello già registrato.
///
/// Il modello viene letto dal registro persistente.
/// Non accetta un modello arbitrario come parametro.
/// Nessuna modifica ai pronostici o agli archivi.
class SmartBetRegisteredFrozenAuditService {
  const SmartBetRegisteredFrozenAuditService();

  Future<SmartBetRegisteredAuditResult> evaluate({
    required SmartBetFrozenModelRegistrationStore store,
    required String modelId,
    required Iterable<SmartBetShadowOutcomeCase> cases,
    required DateTime asOf,
  }) async {
    await store.initialize();

    final matches = store.registrations
        .where((entry) => entry.modelId == modelId)
        .toList();

    if (matches.length != 1) {
      return SmartBetRegisteredAuditResult(
        status: SmartBetRegisteredAuditStatus.missingRegistration,
        modelId: modelId,
        excludedBeforeRegistration: 0,
        audit: null,
      );
    }

    final registration = matches.single;
    final registeredAt = registration.registeredAt.toUtc();
    final frozenAt = registration.model.frozenAt.toUtc();
    final cutoff = asOf.toUtc();

    if (!frozenAt.isBefore(registeredAt) || !registeredAt.isBefore(cutoff)) {
      return SmartBetRegisteredAuditResult(
        status: SmartBetRegisteredAuditStatus.invalidChronology,
        modelId: modelId,
        excludedBeforeRegistration: 0,
        audit: null,
      );
    }

    final subsequent = <SmartBetShadowOutcomeCase>[];
    var excludedBeforeRegistration = 0;

    for (final item in cases) {
      final predictedAt = item.prediction.predictedAt.toUtc();

      // La registrazione deve essere anteriore,
      // non contemporanea, alla previsione.
      if (!registeredAt.isBefore(predictedAt)) {
        excludedBeforeRegistration++;
        continue;
      }

      subsequent.add(item);
    }

    final report = const SmartBetFrozenSnapshotAuditService().evaluate(
      model: registration.model,
      cases: subsequent,
      asOf: cutoff,
    );

    return SmartBetRegisteredAuditResult(
      status: SmartBetRegisteredAuditStatus.evaluated,
      modelId: modelId,
      excludedBeforeRegistration: excludedBeforeRegistration,
      audit: report,
    );
  }
}
