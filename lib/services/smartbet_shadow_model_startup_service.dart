import 'package:flutter/foundation.dart';

import 'smartbet_analysis_history_store.dart';
import 'smartbet_frozen_model_registration_store.dart';
import 'smartbet_frozen_model_snapshot_store.dart';
import 'smartbet_shadow_model_coordinator.dart';

/// Avvia una sola volta la preparazione dei modelli shadow
/// durante la sessione corrente.
///
/// Non modifica pronostici, ranking o schedine.
/// In caso di errore lascia proseguire l'avvio dell'app.
class SmartBetShadowModelStartupService {
  static final instance = SmartBetShadowModelStartupService();

  final Future<List<SmartBetAnalysisRecord>> Function() _loadHistory;
  final DateTime Function() _clock;
  final SmartBetFrozenModelSnapshotStore _modelStore;
  final SmartBetFrozenModelRegistrationStore _registrationStore;

  SmartBetShadowModelStartupService({
    Future<List<SmartBetAnalysisRecord>> Function()? loadHistory,
    DateTime Function()? clock,
    SmartBetFrozenModelSnapshotStore? modelStore,
    SmartBetFrozenModelRegistrationStore? registrationStore,
  }) : _loadHistory = loadHistory ?? _defaultLoadHistory,
       _clock = clock ?? DateTime.now,
       _modelStore = modelStore ?? SmartBetFrozenModelSnapshotStore(),
       _registrationStore =
           registrationStore ?? SmartBetFrozenModelRegistrationStore();

  Future<SmartBetShadowModelPreparationReport?>? _runOnce;

  Future<SmartBetShadowModelPreparationReport?> run() {
    return _runOnce ??= _prepareSafely();
  }

  static Future<List<SmartBetAnalysisRecord>> _defaultLoadHistory() async {
    final historyStore = SmartBetAnalysisHistoryStore.instance;
    await historyStore.initialize();
    return historyStore.records;
  }

  Future<SmartBetShadowModelPreparationReport?> _prepareSafely() async {
    try {
      final history = await _loadHistory();

      final report = await const SmartBetShadowModelCoordinator().prepare(
        history: history,
        asOf: _clock().toUtc(),
        modelStore: _modelStore,
        registrationStore: _registrationStore,
      );

      if (!report.successful) {
        debugPrint(
          'SmartBet shadow startup: '
          '${report.errors.length} errori di preparazione',
        );
      }

      return report;
    } catch (error) {
      debugPrint('SmartBet shadow startup unavailable: $error');

      // Fail-open soltanto per l'avvio dell'app.
      // Nessuna correzione live viene autorizzata.
      return null;
    }
  }
}
