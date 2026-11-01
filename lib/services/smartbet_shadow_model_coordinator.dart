import 'smartbet_analysis_history_store.dart';
import 'smartbet_frozen_model_registration_store.dart';
import 'smartbet_frozen_model_snapshot_store.dart';

class SmartBetShadowModelPreparationReport {
  final DateTime trainingCutoff;
  final int eligibleMarkets;
  final int createdModels;
  final int existingModels;
  final int unavailableModels;
  final List<String> errors;

  const SmartBetShadowModelPreparationReport({
    required this.trainingCutoff,
    required this.eligibleMarkets,
    required this.createdModels,
    required this.existingModels,
    required this.unavailableModels,
    required this.errors,
  });

  bool get successful => errors.isEmpty;
}

/// Prepara una sola versione shadow per motore e mercato.
///
/// Una versione registrata resta invariata: la rotazione
/// dei modelli dovrà avvenire tramite procedura separata.
///
/// Non modifica le probabilità delle analisi o schedine.
class SmartBetShadowModelCoordinator {
  const SmartBetShadowModelCoordinator();

  Future<SmartBetShadowModelPreparationReport> prepare({
    required List<SmartBetAnalysisRecord> history,
    required DateTime asOf,
    required SmartBetFrozenModelSnapshotStore modelStore,
    required SmartBetFrozenModelRegistrationStore registrationStore,
  }) async {
    final now = asOf.toUtc();

    // Addestramento limitato ai risultati già disponibili
    // prima dell'inizio del giorno corrente UTC.
    final cutoff = DateTime.utc(now.year, now.month, now.day);

    await modelStore.initialize();
    await registrationStore.initialize();

    final groups = <(SmartBetAnalysisEngine, String), Set<int>>{};

    for (final record in history) {
      final market = normalizeAnalysisMarket(record.market);
      final kickoff = record.matchDate.toUtc();
      final predicted = record.firstSeenAt.toUtc();
      final resolved = record.resolvedAt?.toUtc();
      final probability = record.probability;

      if (market.isEmpty ||
          market == 'N/D' ||
          record.fixtureId <= 0 ||
          !record.prospectiveEligible ||
          !record.hasActualResult ||
          record.asianSettlement != null ||
          (record.engine == SmartBetAnalysisEngine.diego &&
              record.qualified != true) ||
          (record.status != SmartBetAnalysisStatus.correct &&
              record.status != SmartBetAnalysisStatus.wrong) ||
          probability == null ||
          !probability.isFinite ||
          probability < 0 ||
          probability > 1 ||
          !predicted.isBefore(kickoff) ||
          !kickoff.isBefore(cutoff) ||
          resolved == null ||
          !resolved.isAfter(kickoff) ||
          !resolved.isBefore(cutoff)) {
        continue;
      }

      groups
          .putIfAbsent((record.engine, market), () => <int>{})
          .add(record.fixtureId);
    }

    final eligible =
        groups.entries.where((entry) => entry.value.length >= 50).toList()
          ..sort((a, b) {
            final engine = a.key.$1.name.compareTo(b.key.$1.name);
            if (engine != 0) return engine;
            return a.key.$2.compareTo(b.key.$2);
          });

    var created = 0;
    var existing = 0;
    var unavailable = 0;
    final errors = <String>[];

    for (final entry in eligible) {
      final engine = entry.key.$1;
      final market = entry.key.$2;
      final label = '${engine.name}|$market';

      try {
        // Non sostituire automaticamente un modello
        // già registrato, nemmeno nei giorni successivi.
        final registered = registrationStore.registrations
            .where(
              (item) =>
                  item.model.engine == engine && item.model.market == market,
            )
            .toList();

        if (registered.length > 1) {
          errors.add('$label: registrazioni multiple');
          continue;
        }

        if (registered.isNotEmpty) {
          existing++;
          continue;
        }

        // Riprendi un modello salvato, ma non ancora
        // registrato, senza ricalcolarne i parametri.
        final previouslySaved = modelStore.snapshots
            .where(
              (item) =>
                  item.engine == engine &&
                  item.market == market &&
                  item.frozenAt.toUtc().isBefore(now),
            )
            .toList();

        if (previouslySaved.length > 1) {
          errors.add('$label: modelli salvati multipli');
          continue;
        }

        SmartBetFrozenModelSnapshot? model;

        if (previouslySaved.isNotEmpty) {
          model = previouslySaved.single;
        } else {
          model = SmartBetFrozenModelSnapshot.prepare(
            engine: engine,
            market: market,
            frozenAt: cutoff,
            records: history,
          );

          if (model == null) {
            unavailable++;
            continue;
          }

          model = await modelStore.save(model);
        }

        await registrationStore.register(model);
        created++;
      } catch (error) {
        // Una registrazione fallita non blocca gli altri
        // mercati e non abilita alcuna correzione.
        errors.add('$label: $error');
      }
    }

    return SmartBetShadowModelPreparationReport(
      trainingCutoff: cutoff,
      eligibleMarkets: eligible.length,
      createdModels: created,
      existingModels: existing,
      unavailableModels: unavailable,
      errors: List.unmodifiable(errors),
    );
  }
}
