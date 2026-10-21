import 'smartbet_adaptive_learning_service.dart';
import 'smartbet_analysis_comparison_store.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_learning_snapshot_store.dart';
import 'smartbet_meta_learning_service.dart';

class SmartBetLearningRefreshSummary {
  final int eligibleRecords;
  final int eligiblePairs;

  final bool snapshotCaptured;
  final String? snapshotDayKey;

  const SmartBetLearningRefreshSummary({
    required this.eligibleRecords,
    required this.eligiblePairs,
    required this.snapshotCaptured,
    required this.snapshotDayKey,
  });
}

/// Coordina il learning shadow.
///
/// IMPORTANTE:
/// - non modifica SmartBet;
/// - non modifica Diego;
/// - non modifica probabilità o mercati;
/// - non effettua chiamate AI;
/// - legge esclusivamente lo storico reale P7
///   e aggiorna lo snapshot statistico P9.
class SmartBetLearningCoordinator {
  final SmartBetAnalysisHistoryStore _historyStore;

  final SmartBetAnalysisComparisonStore _comparisonStore;

  final SmartBetLearningSnapshotStore _snapshotStore;

  final SmartBetAdaptiveLearningService _adaptiveService;

  final SmartBetMetaLearningService _metaService;

  SmartBetLearningCoordinator({
    SmartBetAnalysisHistoryStore? historyStore,
    SmartBetAnalysisComparisonStore? comparisonStore,
    SmartBetLearningSnapshotStore? snapshotStore,
    SmartBetAdaptiveLearningService adaptiveService =
        const SmartBetAdaptiveLearningService(),
    SmartBetMetaLearningService metaService =
        const SmartBetMetaLearningService(),
  }) : _historyStore = historyStore ?? SmartBetAnalysisHistoryStore.instance,
       _comparisonStore =
           comparisonStore ?? SmartBetAnalysisComparisonStore.instance,
       _snapshotStore = snapshotStore ?? SmartBetLearningSnapshotStore.instance,
       _adaptiveService = adaptiveService,
       _metaService = metaService;

  Future<SmartBetLearningRefreshSummary> refresh({
    DateTime? generatedAt,
  }) async {
    await Future.wait([
      _historyStore.initialize(),
      _comparisonStore.initialize(),
      _snapshotStore.initialize(),
    ]);

    final records = _historyStore.records;
    final links = _comparisonStore.links;

    final adaptiveReport = _adaptiveService.analyze(
      records,
      generatedAt: generatedAt,
    );

    final metaReport = _metaService.analyze(
      records: records,
      links: links,
      generatedAt: generatedAt,
    );

    // Se non esiste ancora neppure un esito utilizzabile,
    // non creiamo snapshot vuoti.
    if (adaptiveReport.eligibleRecords <= 0 && metaReport.eligiblePairs <= 0) {
      return SmartBetLearningRefreshSummary(
        eligibleRecords: adaptiveReport.eligibleRecords,
        eligiblePairs: metaReport.eligiblePairs,
        snapshotCaptured: false,
        snapshotDayKey: null,
      );
    }

    final snapshot = await _snapshotStore.capture(
      adaptiveReport: adaptiveReport,
      metaReport: metaReport,
      generatedAt: generatedAt,
    );

    return SmartBetLearningRefreshSummary(
      eligibleRecords: adaptiveReport.eligibleRecords,
      eligiblePairs: metaReport.eligiblePairs,
      snapshotCaptured: true,
      snapshotDayKey: snapshot.dayKey,
    );
  }
}
