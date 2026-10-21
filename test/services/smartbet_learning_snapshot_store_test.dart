import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/smartbet_adaptive_learning_service.dart';
import '../../lib/services/smartbet_analysis_history_store.dart';
import '../../lib/services/smartbet_learning_snapshot_store.dart';
import '../../lib/services/smartbet_meta_learning_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SmartBetAdaptiveLearningSegment adaptiveSegment({
    required SmartBetAnalysisEngine engine,
    required int sampleSize,
    required double accuracy,
  }) {
    return SmartBetAdaptiveLearningSegment(
      engine: engine,
      dimension: SmartBetAdaptiveLearningDimension.overall,
      market: null,
      league: null,
      probabilityBand: null,
      sampleSize: sampleSize,
      correct: (sampleSize * accuracy / 100).round(),
      wrong: sampleSize - (sampleSize * accuracy / 100).round(),
      probabilitySampleSize: sampleSize,
      accuracy: accuracy,
      averagePredictedProbability: 70.0,
      calibrationGap: accuracy - 70.0,
      brierScore: 0.20,
      signal: SmartBetAdaptiveLearningService.signalForSample(sampleSize),
    );
  }

  SmartBetAdaptiveLearningReport adaptiveReport({
    required int eligibleRecords,
    int smartSample = 50,
    int diegoSample = 50,
    double smartAccuracy = 70.0,
    double diegoAccuracy = 65.0,
  }) {
    return SmartBetAdaptiveLearningReport(
      generatedAt: DateTime.utc(2026, 10, 22),
      eligibleRecords: eligibleRecords,
      segments: [
        adaptiveSegment(
          engine: SmartBetAnalysisEngine.smartBet,
          sampleSize: smartSample,
          accuracy: smartAccuracy,
        ),
        adaptiveSegment(
          engine: SmartBetAnalysisEngine.diego,
          sampleSize: diegoSample,
          accuracy: diegoAccuracy,
        ),
      ],
    );
  }

  SmartBetMetaLearningReport metaReport({
    required int eligiblePairs,
    int linkedPairs = 50,
    double smartAccuracy = 70.0,
    double diegoAccuracy = 64.0,
  }) {
    final advantage = smartAccuracy - diegoAccuracy;

    return SmartBetMetaLearningReport(
      generatedAt: DateTime.utc(2026, 10, 22),
      linkedPairs: linkedPairs,
      eligiblePairs: eligiblePairs,
      excludedMissingRecords: 0,
      excludedNonProspective: 0,
      excludedPendingOrUnsupported: 0,
      excludedUnqualifiedDiego: 0,
      segments: [
        SmartBetMetaLearningSegment(
          dimension: SmartBetMetaLearningDimension.overall,
          league: null,
          smartBetMarket: null,
          diegoMarket: null,
          probabilityPair: null,
          sampleSize: eligiblePairs,
          bothCorrect: 20,
          smartBetOnlyCorrect: 15,
          diegoOnlyCorrect: 12,
          bothWrong: 3,
          smartBetAccuracy: smartAccuracy,
          diegoAccuracy: diegoAccuracy,
          advantagePercentagePoints: advantage,
          signal: SmartBetAdaptiveLearningService.signalForSample(
            eligiblePairs,
          ),
          preference: eligiblePairs < 50
              ? SmartBetMetaLearningPreference.insufficientData
              : advantage >= 3.0
              ? SmartBetMetaLearningPreference.smartBet
              : advantage <= -3.0
              ? SmartBetMetaLearningPreference.diego
              : SmartBetMetaLearningPreference.balanced,
        ),
      ],
    );
  }

  test('salva il primo snapshot', () async {
    final store = SmartBetLearningSnapshotStore();

    final snapshot = await store.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 100),
      metaReport: metaReport(eligiblePairs: 50),
      generatedAt: DateTime.utc(2026, 10, 22, 10),
    );

    expect(store.snapshots.length, 1);
    expect(snapshot.eligibleRecords, 100);
    expect(snapshot.smartBetAccuracy, 70.0);
    expect(snapshot.diegoAccuracy, 65.0);
    expect(snapshot.metaPreference, SmartBetMetaLearningPreference.smartBet);
  });

  test('stesso giorno aggiorna snapshot con più evidenza', () async {
    final store = SmartBetLearningSnapshotStore();

    await store.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 100),
      metaReport: metaReport(eligiblePairs: 50),
      generatedAt: DateTime.utc(2026, 10, 22, 9),
    );

    await store.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 120, smartAccuracy: 72.0),
      metaReport: metaReport(eligiblePairs: 60),
      generatedAt: DateTime.utc(2026, 10, 22, 20),
    );

    expect(store.snapshots.length, 1);

    final latest = store.latest!;

    expect(latest.eligibleRecords, 120);
    expect(latest.smartBetAccuracy, 72.0);
    expect(latest.eligiblePairs, 60);
  });

  test('stesso giorno non sostituisce dati con meno evidenza', () async {
    final store = SmartBetLearningSnapshotStore();

    await store.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 120),
      metaReport: metaReport(eligiblePairs: 60),
      generatedAt: DateTime.utc(2026, 10, 22, 9),
    );

    await store.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 80, smartAccuracy: 30.0),
      metaReport: metaReport(eligiblePairs: 20),
      generatedAt: DateTime.utc(2026, 10, 22, 20),
    );

    expect(store.snapshots.length, 1);

    expect(store.latest!.eligibleRecords, 120);

    expect(store.latest!.smartBetAccuracy, 70.0);
  });

  test('giorni diversi creano snapshot distinti', () async {
    final store = SmartBetLearningSnapshotStore();

    await store.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 100),
      metaReport: metaReport(eligiblePairs: 50),
      generatedAt: DateTime.utc(2026, 10, 22),
    );

    await store.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 110),
      metaReport: metaReport(eligiblePairs: 55),
      generatedAt: DateTime.utc(2026, 10, 23),
    );

    expect(store.snapshots.length, 2);

    expect(store.snapshots.first.dayKey, '2026-10-22');

    expect(store.snapshots.last.dayKey, '2026-10-23');
  });

  test('persistenza conserva gli snapshot', () async {
    final first = SmartBetLearningSnapshotStore();

    await first.capture(
      adaptiveReport: adaptiveReport(eligibleRecords: 125),
      metaReport: metaReport(eligiblePairs: 62),
      generatedAt: DateTime.utc(2026, 10, 22, 12),
    );

    final second = SmartBetLearningSnapshotStore();

    await second.initialize();

    expect(second.snapshots.length, 1);

    expect(second.latest!.eligibleRecords, 125);

    expect(second.latest!.eligiblePairs, 62);

    expect(second.latest!.dayKey, '2026-10-22');
  });

  test('snapshot conserva calibrazione e meta confronto', () async {
    final store = SmartBetLearningSnapshotStore();

    final snapshot = await store.capture(
      adaptiveReport: adaptiveReport(
        eligibleRecords: 100,
        smartAccuracy: 75.0,
        diegoAccuracy: 60.0,
      ),
      metaReport: metaReport(
        eligiblePairs: 50,
        smartAccuracy: 74.0,
        diegoAccuracy: 62.0,
      ),
      generatedAt: DateTime.utc(2026, 10, 22),
    );

    expect(snapshot.smartBetCalibrationGap, 5.0);

    expect(snapshot.diegoCalibrationGap, -10.0);

    expect(snapshot.metaAdvantagePoints, 12.0);

    expect(snapshot.metaSmartBetAccuracy, 74.0);

    expect(snapshot.metaDiegoAccuracy, 62.0);
  });
}
