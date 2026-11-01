import 'smartbet_frozen_model_registration_store.dart';
import 'smartbet_registered_frozen_audit_service.dart';
import 'smartbet_shadow_outcome_service.dart';

class SmartBetProspectiveModelAuditReport {
  final SmartBetRegisteredAuditResult registeredAudit;
  final int excludedWithoutModel;
  final int excludedWrongModel;
  final int excludedInvalidBinding;

  const SmartBetProspectiveModelAuditReport({
    required this.registeredAudit,
    required this.excludedWithoutModel,
    required this.excludedWrongModel,
    required this.excludedInvalidBinding,
  });

  int get validatedFixtures => registeredAudit.audit?.validationFixtures ?? 0;

  double? get brierImprovement => registeredAudit.audit?.brierImprovement;

  /// Informazione diagnostica, non autorizzazione live.
  bool get exploratoryEvidenceAvailable =>
      registeredAudit.evaluated &&
      (registeredAudit.audit?.enoughForExploratoryReview ?? false);
}

/// Audit prospettico locale di un modello registrato.
///
/// Accetta soltanto snapshot con associazione al modello
/// creata al momento dell'acquisizione della previsione.
///
/// Non modifica probabilità, schedine o archivi.
/// Non certifica l'orologio locale.
class SmartBetProspectiveModelAuditService {
  const SmartBetProspectiveModelAuditService();

  Future<SmartBetProspectiveModelAuditReport> evaluate({
    required SmartBetFrozenModelRegistrationStore store,
    required String modelId,
    required Iterable<SmartBetShadowOutcomeCase> cases,
    required DateTime asOf,
  }) async {
    await store.initialize();

    final registrations = store.registrations
        .where((item) => item.modelId == modelId)
        .toList();

    final matchingRegistration = registrations.length == 1
        ? registrations.single
        : null;

    final accepted = <SmartBetShadowOutcomeCase>[];

    var withoutModel = 0;
    var wrongModel = 0;
    var invalidBinding = 0;

    for (final item in cases) {
      final prediction = item.prediction;
      final linkedId = prediction.shadowModelId;
      final linkedAt = prediction.shadowModelLinkedAt?.toUtc();

      if (linkedId == null || linkedId.isEmpty) {
        withoutModel++;
        continue;
      }

      if (linkedId != modelId) {
        wrongModel++;
        continue;
      }

      if (matchingRegistration == null) {
        invalidBinding++;
        continue;
      }

      final registeredAt = matchingRegistration.registeredAt.toUtc();
      final predictedAt = prediction.predictedAt.toUtc();
      final kickoff = item.record.matchDate.toUtc();

      final validBinding =
          linkedAt != null &&
          registeredAt.isBefore(predictedAt) &&
          registeredAt.isBefore(linkedAt) &&
          !linkedAt.isBefore(predictedAt) &&
          linkedAt.difference(predictedAt) <= const Duration(minutes: 5) &&
          linkedAt.isBefore(kickoff) &&
          linkedAt.isBefore(asOf.toUtc()) &&
          item.record.firstSeenAt.toUtc().isAtSameMomentAs(predictedAt);

      if (!validBinding) {
        invalidBinding++;
        continue;
      }

      accepted.add(item);
    }

    // L'auditor esistente controlla ulteriormente:
    // motore, mercato, chiavi, esito, duplicati, date
    // delle partite e disponibilità del risultato.
    final registeredAudit = await const SmartBetRegisteredFrozenAuditService()
        .evaluate(store: store, modelId: modelId, cases: accepted, asOf: asOf);

    return SmartBetProspectiveModelAuditReport(
      registeredAudit: registeredAudit,
      excludedWithoutModel: withoutModel,
      excludedWrongModel: wrongModel,
      excludedInvalidBinding: invalidBinding,
    );
  }
}
