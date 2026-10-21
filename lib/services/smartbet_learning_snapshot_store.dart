import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_adaptive_learning_service.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_meta_learning_service.dart';

class SmartBetLearningSnapshot {
  final DateTime generatedAt;

  final int eligibleRecords;

  final int smartBetSampleSize;
  final double? smartBetAccuracy;
  final double? smartBetAverageProbability;
  final double? smartBetCalibrationGap;
  final double? smartBetBrierScore;

  final int diegoSampleSize;
  final double? diegoAccuracy;
  final double? diegoAverageProbability;
  final double? diegoCalibrationGap;
  final double? diegoBrierScore;

  final int linkedPairs;
  final int eligiblePairs;

  final double? metaSmartBetAccuracy;
  final double? metaDiegoAccuracy;
  final double? metaAdvantagePoints;

  final SmartBetMetaLearningPreference? metaPreference;

  final int strongAdaptiveSignals;
  final int strongMetaSignals;

  const SmartBetLearningSnapshot({
    required this.generatedAt,
    required this.eligibleRecords,
    required this.smartBetSampleSize,
    required this.smartBetAccuracy,
    required this.smartBetAverageProbability,
    required this.smartBetCalibrationGap,
    required this.smartBetBrierScore,
    required this.diegoSampleSize,
    required this.diegoAccuracy,
    required this.diegoAverageProbability,
    required this.diegoCalibrationGap,
    required this.diegoBrierScore,
    required this.linkedPairs,
    required this.eligiblePairs,
    required this.metaSmartBetAccuracy,
    required this.metaDiegoAccuracy,
    required this.metaAdvantagePoints,
    required this.metaPreference,
    required this.strongAdaptiveSignals,
    required this.strongMetaSignals,
  });

  int get evidenceScore => eligibleRecords + eligiblePairs;

  String get dayKey {
    final utc = generatedAt.toUtc();

    final month = utc.month.toString().padLeft(2, '0');

    final day = utc.day.toString().padLeft(2, '0');

    return '${utc.year}-$month-$day';
  }

  Map<String, dynamic> toJson() {
    return {
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'eligibleRecords': eligibleRecords,
      'smartBetSampleSize': smartBetSampleSize,
      'smartBetAccuracy': smartBetAccuracy,
      'smartBetAverageProbability': smartBetAverageProbability,
      'smartBetCalibrationGap': smartBetCalibrationGap,
      'smartBetBrierScore': smartBetBrierScore,
      'diegoSampleSize': diegoSampleSize,
      'diegoAccuracy': diegoAccuracy,
      'diegoAverageProbability': diegoAverageProbability,
      'diegoCalibrationGap': diegoCalibrationGap,
      'diegoBrierScore': diegoBrierScore,
      'linkedPairs': linkedPairs,
      'eligiblePairs': eligiblePairs,
      'metaSmartBetAccuracy': metaSmartBetAccuracy,
      'metaDiegoAccuracy': metaDiegoAccuracy,
      'metaAdvantagePoints': metaAdvantagePoints,
      'metaPreference': metaPreference?.name,
      'strongAdaptiveSignals': strongAdaptiveSignals,
      'strongMetaSignals': strongMetaSignals,
    };
  }

  static SmartBetLearningSnapshot? fromJson(Map<String, dynamic> json) {
    final generatedAt = DateTime.tryParse(
      json['generatedAt']?.toString() ?? '',
    );

    if (generatedAt == null) {
      return null;
    }

    return SmartBetLearningSnapshot(
      generatedAt: generatedAt.toUtc(),
      eligibleRecords: _toInt(json['eligibleRecords']) ?? 0,
      smartBetSampleSize: _toInt(json['smartBetSampleSize']) ?? 0,
      smartBetAccuracy: _toDouble(json['smartBetAccuracy']),
      smartBetAverageProbability: _toDouble(json['smartBetAverageProbability']),
      smartBetCalibrationGap: _toDouble(json['smartBetCalibrationGap']),
      smartBetBrierScore: _toDouble(json['smartBetBrierScore']),
      diegoSampleSize: _toInt(json['diegoSampleSize']) ?? 0,
      diegoAccuracy: _toDouble(json['diegoAccuracy']),
      diegoAverageProbability: _toDouble(json['diegoAverageProbability']),
      diegoCalibrationGap: _toDouble(json['diegoCalibrationGap']),
      diegoBrierScore: _toDouble(json['diegoBrierScore']),
      linkedPairs: _toInt(json['linkedPairs']) ?? 0,
      eligiblePairs: _toInt(json['eligiblePairs']) ?? 0,
      metaSmartBetAccuracy: _toDouble(json['metaSmartBetAccuracy']),
      metaDiegoAccuracy: _toDouble(json['metaDiegoAccuracy']),
      metaAdvantagePoints: _toDouble(json['metaAdvantagePoints']),
      metaPreference: _metaPreferenceFromName(
        json['metaPreference']?.toString(),
      ),
      strongAdaptiveSignals: _toInt(json['strongAdaptiveSignals']) ?? 0,
      strongMetaSignals: _toInt(json['strongMetaSignals']) ?? 0,
    );
  }
}

class SmartBetLearningSnapshotStore extends ChangeNotifier {
  SmartBetLearningSnapshotStore();

  static final SmartBetLearningSnapshotStore instance =
      SmartBetLearningSnapshotStore();

  static const String _storageKey = 'smartbet_learning_snapshots_v1';

  static const int _maximumSnapshots = 730;

  SharedPreferences? _preferences;

  bool _initialized = false;

  final List<SmartBetLearningSnapshot> _snapshots = [];

  bool get initialized => _initialized;

  List<SmartBetLearningSnapshot> get snapshots {
    final values = List<SmartBetLearningSnapshot>.from(_snapshots);

    values.sort((a, b) => a.generatedAt.compareTo(b.generatedAt));

    return List.unmodifiable(values);
  }

  SmartBetLearningSnapshot? get latest {
    if (_snapshots.isEmpty) {
      return null;
    }

    final values = List<SmartBetLearningSnapshot>.from(_snapshots);

    values.sort((a, b) => b.generatedAt.compareTo(a.generatedAt));

    return values.first;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _preferences ??= await SharedPreferences.getInstance();

    await _load();

    _initialized = true;

    notifyListeners();
  }

  Future<SmartBetLearningSnapshot> capture({
    required SmartBetAdaptiveLearningReport adaptiveReport,
    required SmartBetMetaLearningReport metaReport,
    DateTime? generatedAt,
  }) async {
    await initialize();

    final timestamp = (generatedAt ?? DateTime.now()).toUtc();

    final smartBetOverall = _overallForEngine(
      adaptiveReport,
      SmartBetAnalysisEngine.smartBet,
    );

    final diegoOverall = _overallForEngine(
      adaptiveReport,
      SmartBetAnalysisEngine.diego,
    );

    final metaOverall = metaReport.overall;

    final snapshot = SmartBetLearningSnapshot(
      generatedAt: timestamp,
      eligibleRecords: adaptiveReport.eligibleRecords,
      smartBetSampleSize: smartBetOverall?.sampleSize ?? 0,
      smartBetAccuracy: smartBetOverall?.accuracy,
      smartBetAverageProbability: smartBetOverall?.averagePredictedProbability,
      smartBetCalibrationGap: smartBetOverall?.calibrationGap,
      smartBetBrierScore: smartBetOverall?.brierScore,
      diegoSampleSize: diegoOverall?.sampleSize ?? 0,
      diegoAccuracy: diegoOverall?.accuracy,
      diegoAverageProbability: diegoOverall?.averagePredictedProbability,
      diegoCalibrationGap: diegoOverall?.calibrationGap,
      diegoBrierScore: diegoOverall?.brierScore,
      linkedPairs: metaReport.linkedPairs,
      eligiblePairs: metaReport.eligiblePairs,
      metaSmartBetAccuracy: metaOverall?.smartBetAccuracy,
      metaDiegoAccuracy: metaOverall?.diegoAccuracy,
      metaAdvantagePoints: metaOverall?.advantagePercentagePoints,
      metaPreference: metaOverall?.preference,
      strongAdaptiveSignals: adaptiveReport.strongCandidates().length,
      strongMetaSignals: metaReport.strongSignals().length,
    );

    final existingIndex = _snapshots.indexWhere(
      (item) => item.dayKey == snapshot.dayKey,
    );

    if (existingIndex >= 0) {
      final existing = _snapshots[existingIndex];

      if (snapshot.evidenceScore >= existing.evidenceScore) {
        _snapshots[existingIndex] = snapshot;

        await _save();

        notifyListeners();

        return snapshot;
      }

      return existing;
    }

    _snapshots.add(snapshot);

    _trimOldSnapshots();

    await _save();

    notifyListeners();

    return snapshot;
  }

  Future<void> clear() async {
    await initialize();

    _snapshots.clear();

    await _save();

    notifyListeners();
  }

  void _trimOldSnapshots() {
    if (_snapshots.length <= _maximumSnapshots) {
      return;
    }

    _snapshots.sort((a, b) => a.generatedAt.compareTo(b.generatedAt));

    final excess = _snapshots.length - _maximumSnapshots;

    _snapshots.removeRange(0, excess);
  }

  SmartBetAdaptiveLearningSegment? _overallForEngine(
    SmartBetAdaptiveLearningReport report,
    SmartBetAnalysisEngine engine,
  ) {
    for (final segment in report.segments) {
      if (segment.engine == engine &&
          segment.dimension == SmartBetAdaptiveLearningDimension.overall) {
        return segment;
      }
    }

    return null;
  }

  Future<void> _load() async {
    final prefs = _preferences;

    if (prefs == null) {
      return;
    }

    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return;
      }

      _snapshots.clear();

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final snapshot = SmartBetLearningSnapshot.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (snapshot != null) {
          _snapshots.add(snapshot);
        }
      }

      _trimOldSnapshots();
    } catch (e) {
      debugPrint('SmartBet learning snapshot load error: $e');
    }
  }

  Future<void> _save() async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();

    try {
      await prefs.setString(
        _storageKey,
        jsonEncode(_snapshots.map((snapshot) => snapshot.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('SmartBet learning snapshot save error: $e');
    }
  }
}

SmartBetMetaLearningPreference? _metaPreferenceFromName(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  for (final preference in SmartBetMetaLearningPreference.values) {
    if (preference.name == value) {
      return preference;
    }
  }

  return null;
}

int? _toInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  return int.tryParse(value?.toString() ?? '');
}

double? _toDouble(dynamic value) {
  if (value is double) {
    return value;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '');
}
