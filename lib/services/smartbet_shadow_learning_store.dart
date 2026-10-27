import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_analysis_history_store.dart';
import 'smartbet_historical_calibration_service.dart';

class SmartBetShadowPrediction {
  final String key;
  final String engine;
  final String market;
  final int fixtureId;
  final DateTime predictedAt;
  final double originalProbability;
  final double calibratedProbability;
  final int trainingSampleSize;
  final bool calibrationApplied;

  const SmartBetShadowPrediction({
    required this.key,
    required this.engine,
    required this.market,
    required this.fixtureId,
    required this.predictedAt,
    required this.originalProbability,
    required this.calibratedProbability,
    required this.trainingSampleSize,
    required this.calibrationApplied,
  });

  bool get adjusted =>
      (calibratedProbability - originalProbability).abs() > 1e-12;

  Map<String, dynamic> toJson() => {
    'key': key,
    'engine': engine,
    'market': market,
    'fixtureId': fixtureId,
    'predictedAt': predictedAt.toUtc().toIso8601String(),
    'originalProbability': originalProbability,
    'calibratedProbability': calibratedProbability,
    'trainingSampleSize': trainingSampleSize,
    'calibrationApplied': calibrationApplied,
  };

  factory SmartBetShadowPrediction.fromJson(Map<String, dynamic> json) {
    return SmartBetShadowPrediction(
      key: json['key'] as String,
      engine: json['engine'] as String,
      market: json['market'] as String,
      fixtureId: (json['fixtureId'] as num).toInt(),
      predictedAt: DateTime.parse(json['predictedAt'] as String).toUtc(),
      originalProbability: (json['originalProbability'] as num).toDouble(),
      calibratedProbability: (json['calibratedProbability'] as num).toDouble(),
      trainingSampleSize: (json['trainingSampleSize'] as num).toInt(),
      calibrationApplied: json['calibrationApplied'] == true,
    );
  }
}

/// Memoria separata delle probabilità sperimentali.
/// Non modifica lo storico originale o le schedine.
class SmartBetShadowLearningStore {
  SmartBetShadowLearningStore();

  static final instance = SmartBetShadowLearningStore();

  static const storageKey = 'smartbet_shadow_learning_v1';

  SharedPreferences? _prefs;
  bool _initialized = false;

  final Map<String, SmartBetShadowPrediction> _predictions = {};

  List<SmartBetShadowPrediction> get predictions =>
      List.unmodifiable(_predictions.values);

  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;

            try {
              final prediction = SmartBetShadowPrediction.fromJson(
                Map<String, dynamic>.from(item),
              );

              _predictions[prediction.key] = prediction;
            } catch (_) {
              // Un record non valido non blocca gli altri.
            }
          }
        }
      } catch (_) {
        // L'archivio storico originale resta separato.
      }
    }

    _initialized = true;
  }

  Future<SmartBetShadowPrediction?> capture({
    required SmartBetAnalysisRecord record,
    required List<SmartBetAnalysisRecord> history,
  }) async {
    await initialize();

    // Non ricalcolare una previsione già memorizzata.
    final existing = _predictions[record.key];
    if (existing != null) return existing;

    if (!record.prospectiveEligible ||
        record.status != SmartBetAnalysisStatus.pending) {
      return null;
    }

    final probability = record.probability;

    if (probability == null ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1) {
      return null;
    }

    final result = const SmartBetHistoricalCalibrationService().evaluate(
      engine: record.engine,
      market: record.market,
      probability: probability,
      asOf: record.firstSeenAt,
      records: history,
      fixtureId: record.fixtureId,
    );

    final snapshot = SmartBetShadowPrediction(
      key: record.key,
      engine: record.engine.name,
      market: record.market,
      fixtureId: record.fixtureId,
      predictedAt: record.firstSeenAt,
      originalProbability: result.original,
      calibratedProbability: result.calibrated,
      trainingSampleSize: result.sampleSize,
      calibrationApplied: result.applied,
    );

    final prefs = _prefs ??= await SharedPreferences.getInstance();

    final next = [..._predictions.values, snapshot];

    final saved = await prefs.setString(
      storageKey,
      jsonEncode(next.map((p) => p.toJson()).toList()),
    );

    if (!saved) {
      throw StateError('Impossibile salvare lo snapshot shadow');
    }

    _predictions[snapshot.key] = snapshot;
    return snapshot;
  }
}
