import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/smartbet_analysis_comparison_store.dart';
import '../../lib/services/smartbet_analysis_history_store.dart';
import '../../lib/services/smartbet_learning_coordinator.dart';
import '../../lib/services/smartbet_learning_snapshot_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> addSettledPair({
    required SmartBetAnalysisHistoryStore history,
    required SmartBetAnalysisComparisonStore comparisons,
    required int fixtureId,
    String smartMarket = '1X',
    String diegoMarket = 'OVER 2.5',
    int homeGoals = 2,
    int awayGoals = 1,
  }) async {
    final matchDate = DateTime.utc(2026, 10, 25, 20, 45);

    final recordedAt = DateTime.utc(2026, 10, 20, 10);

    final smart = await history.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: fixtureId,
      homeTeam: 'Inter',
      awayTeam: 'Roma',
      league: 'Serie A',
      country: 'Italy',
      matchDate: matchDate,
      market: smartMarket,
      probability: 0.72,
      smartScore: 70,
      recordedAt: recordedAt,
    );

    final diego = await history.registerAnalysis(
      engine: SmartBetAnalysisEngine.diego,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: fixtureId,
      homeTeam: 'Inter',
      awayTeam: 'Roma',
      league: 'Serie A',
      country: 'Italy',
      matchDate: matchDate,
      market: diegoMarket,
      probability: 0.65,
      confidence: 75,
      classification: 'QUALIFIED VALUE',
      qualified: true,
      recordedAt: recordedAt,
    );

    expect(smart, isNotNull);
    expect(diego, isNotNull);

    await comparisons.registerPair(
      smartBet: smart!,
      diego: diego!,
      source: SmartBetAnalysisSource.analysis,
      recordedAt: recordedAt,
    );

    await history.registerActualResult(
      fixtureId: fixtureId,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
    );
  }

  test('senza esiti non crea snapshot vuoto', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final snapshots = SmartBetLearningSnapshotStore();

    final coordinator = SmartBetLearningCoordinator(
      historyStore: history,
      comparisonStore: comparisons,
      snapshotStore: snapshots,
    );

    final summary = await coordinator.refresh(
      generatedAt: DateTime.utc(2026, 10, 26, 10),
    );

    expect(summary.eligibleRecords, 0);
    expect(summary.eligiblePairs, 0);
    expect(summary.snapshotCaptured, isFalse);

    expect(snapshots.snapshots, isEmpty);
  });

  test('esiti reali producono automaticamente snapshot learning', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final snapshots = SmartBetLearningSnapshotStore();

    await addSettledPair(
      history: history,
      comparisons: comparisons,
      fixtureId: 100,
    );

    final coordinator = SmartBetLearningCoordinator(
      historyStore: history,
      comparisonStore: comparisons,
      snapshotStore: snapshots,
    );

    final summary = await coordinator.refresh(
      generatedAt: DateTime.utc(2026, 10, 26, 10),
    );

    expect(summary.eligibleRecords, 2);
    expect(summary.eligiblePairs, 1);
    expect(summary.snapshotCaptured, isTrue);
    expect(summary.snapshotDayKey, '2026-10-26');

    expect(snapshots.snapshots.length, 1);

    final snapshot = snapshots.latest!;

    expect(snapshot.smartBetSampleSize, 1);
    expect(snapshot.diegoSampleSize, 1);
    expect(snapshot.eligiblePairs, 1);
  });

  test('nuovi risultati aggiornano snapshot dello stesso giorno', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final snapshots = SmartBetLearningSnapshotStore();

    final coordinator = SmartBetLearningCoordinator(
      historyStore: history,
      comparisonStore: comparisons,
      snapshotStore: snapshots,
    );

    await addSettledPair(
      history: history,
      comparisons: comparisons,
      fixtureId: 200,
    );

    await coordinator.refresh(generatedAt: DateTime.utc(2026, 10, 26, 10));

    expect(snapshots.latest!.eligibleRecords, 2);

    await addSettledPair(
      history: history,
      comparisons: comparisons,
      fixtureId: 201,
      smartMarket: 'GOAL',
      diegoMarket: '1X',
    );

    await coordinator.refresh(generatedAt: DateTime.utc(2026, 10, 26, 20));

    expect(snapshots.snapshots.length, 1);

    expect(snapshots.latest!.eligibleRecords, 4);

    expect(snapshots.latest!.eligiblePairs, 2);
  });

  test('giorno successivo conserva una nuova fotografia', () async {
    final history = SmartBetAnalysisHistoryStore();

    final comparisons = SmartBetAnalysisComparisonStore();

    final snapshots = SmartBetLearningSnapshotStore();

    final coordinator = SmartBetLearningCoordinator(
      historyStore: history,
      comparisonStore: comparisons,
      snapshotStore: snapshots,
    );

    await addSettledPair(
      history: history,
      comparisons: comparisons,
      fixtureId: 300,
    );

    await coordinator.refresh(generatedAt: DateTime.utc(2026, 10, 26, 10));

    await coordinator.refresh(generatedAt: DateTime.utc(2026, 10, 27, 10));

    expect(snapshots.snapshots.length, 2);

    expect(snapshots.snapshots.first.dayKey, '2026-10-26');

    expect(snapshots.snapshots.last.dayKey, '2026-10-27');
  });
}
