import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// P21C: fotografia prepartita, locale e separata dallo storico ufficiale.
/// Nessuna quota bookmaker viene conservata o usata nel modello.
class SmartBetSimulationShadowSnapshot {
  final int fixtureId;
  final String engine;
  final DateTime matchDate;
  final DateTime capturedAt;
  final String modelVersion;
  final double expectedHomeGoals;
  final double expectedAwayGoals;
  final double dataQuality;
  final Map<String, double> originalProbabilities;
  final Map<String, double> simulatedProbabilities;
  final List<String> unsupportedMarkets;

  SmartBetSimulationShadowSnapshot({
    required this.fixtureId,
    required this.engine,
    required this.matchDate,
    required this.capturedAt,
    required this.modelVersion,
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
    required this.dataQuality,
    required Map<String, double> originalProbabilities,
    required Map<String, double> simulatedProbabilities,
    required List<String> unsupportedMarkets,
  }) : originalProbabilities = Map.unmodifiable(originalProbabilities),
       simulatedProbabilities = Map.unmodifiable(simulatedProbabilities),
       unsupportedMarkets = List.unmodifiable(unsupportedMarkets) {
    if (fixtureId <= 0 ||
        engine.isEmpty ||
        modelVersion.isEmpty ||
        !capturedAt.toUtc().isBefore(matchDate.toUtc()) ||
        !expectedHomeGoals.isFinite ||
        !expectedAwayGoals.isFinite ||
        expectedHomeGoals <= 0 ||
        expectedAwayGoals <= 0 ||
        !dataQuality.isFinite ||
        dataQuality < 0 ||
        dataQuality > 1) {
      throw ArgumentError('Snapshot P21C non valido o non prepartita');
    }
    for (final probabilities in [
      this.originalProbabilities,
      this.simulatedProbabilities,
    ]) {
      for (final entry in probabilities.entries) {
        if (entry.key.trim().isEmpty ||
            !entry.value.isFinite ||
            entry.value < 0 ||
            entry.value > 1) {
          throw ArgumentError('Probabilita P21C non valida: ${entry.key}');
        }
      }
    }
  }

  String get key => '$engine|$fixtureId';

  Map<String, dynamic> toJson() => {
    'fixtureId': fixtureId,
    'engine': engine,
    'matchDate': matchDate.toUtc().toIso8601String(),
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'modelVersion': modelVersion,
    'expectedHomeGoals': expectedHomeGoals,
    'expectedAwayGoals': expectedAwayGoals,
    'dataQuality': dataQuality,
    'originalProbabilities': originalProbabilities,
    'simulatedProbabilities': simulatedProbabilities,
    'unsupportedMarkets': unsupportedMarkets,
  };

  static SmartBetSimulationShadowSnapshot fromJson(Map<String, dynamic> json) {
    Map<String, double> probabilities(String key) => (json[key] as Map).map(
      (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
    );
    return SmartBetSimulationShadowSnapshot(
      fixtureId: (json['fixtureId'] as num).toInt(),
      engine: json['engine'] as String,
      matchDate: DateTime.parse(json['matchDate'] as String),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      modelVersion: json['modelVersion'] as String,
      expectedHomeGoals: (json['expectedHomeGoals'] as num).toDouble(),
      expectedAwayGoals: (json['expectedAwayGoals'] as num).toDouble(),
      dataQuality: (json['dataQuality'] as num).toDouble(),
      originalProbabilities: probabilities('originalProbabilities'),
      simulatedProbabilities: probabilities('simulatedProbabilities'),
      unsupportedMarkets: (json['unsupportedMarkets'] as List).cast<String>(),
    );
  }
}

/// Uno snapshot per partita e motore. Il primo resta immutabile.
/// Le scritture concorrenti sullo stesso oggetto sono serializzate.
class SmartBetSimulationShadowStore {
  SmartBetSimulationShadowStore();

  static final SmartBetSimulationShadowStore instance =
      SmartBetSimulationShadowStore();

  static const String storageKey = 'smartbet_p21c_simulation_shadow_v1';

  SharedPreferences? _preferences;
  bool _initialized = false;
  final List<SmartBetSimulationShadowSnapshot> _snapshots = [];
  Future<void> _pending = Future<void>.value();

  List<SmartBetSimulationShadowSnapshot> get snapshots =>
      List.unmodifiable(_snapshots);

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    final loaded = <SmartBetSimulationShadowSnapshot>[];
    if (raw != null && raw.isNotEmpty) {
      final json = jsonDecode(raw);
      if (json is! List) throw const FormatException('Snapshot P21C corrotti');
      for (final entry in json) {
        loaded.add(
          SmartBetSimulationShadowSnapshot.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        );
      }
    }
    _snapshots
      ..clear()
      ..addAll(loaded);
    _preferences = preferences;
    _initialized = true;
  }

  Future<bool> saveFirst(SmartBetSimulationShadowSnapshot snapshot) {
    final task = _pending.then((_) async {
      await initialize();
      if (_snapshots.any((old) => old.key == snapshot.key)) return false;
      final next = [..._snapshots, snapshot];
      final saved = await _preferences!.setString(
        storageKey,
        jsonEncode(next.map((s) => s.toJson()).toList()),
      );
      if (!saved) throw StateError('Salvataggio snapshot P21C fallito');
      _snapshots.add(snapshot);
      return true;
    });
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }
}
