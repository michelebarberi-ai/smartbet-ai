import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_analysis_history_store.dart';
import 'smartbet_historical_calibration_service.dart';

class SmartBetFrozenModelSnapshot {
  static const algorithmVersion = 'historical-gap-shrinkage-v1';

  final String id;
  final SmartBetAnalysisEngine engine;
  final String market;
  final DateTime frozenAt;
  final int trainingFixtures;
  final double adjustment;

  const SmartBetFrozenModelSnapshot._({
    required this.id,
    required this.engine,
    required this.market,
    required this.frozenAt,
    required this.trainingFixtures,
    required this.adjustment,
  });

  static String _idFor(
    SmartBetAnalysisEngine engine,
    String market,
    DateTime frozenAt,
  ) =>
      '$algorithmVersion|${engine.name}|$market|'
      '${frozenAt.toUtc().toIso8601String()}';

  /// Costruisce un modello soltanto usando risultati
  /// già risolti prima del congelamento.
  static SmartBetFrozenModelSnapshot? prepare({
    required SmartBetAnalysisEngine engine,
    required String market,
    required DateTime frozenAt,
    required Iterable<SmartBetAnalysisRecord> records,
  }) {
    final normalized = normalizeAnalysisMarket(market);
    final cutoff = frozenAt.toUtc();

    if (normalized.isEmpty || normalized == 'N/D') {
      return null;
    }

    final candidates =
        records.where((record) {
          final kickoff = record.matchDate.toUtc();
          final predicted = record.firstSeenAt.toUtc();
          final resolved = record.resolvedAt?.toUtc();
          final p = record.probability;

          return record.engine == engine &&
              normalizeAnalysisMarket(record.market) == normalized &&
              record.fixtureId > 0 &&
              record.prospectiveEligible &&
              record.hasActualResult &&
              record.asianSettlement == null &&
              (engine != SmartBetAnalysisEngine.diego ||
                  record.qualified == true) &&
              (record.status == SmartBetAnalysisStatus.correct ||
                  record.status == SmartBetAnalysisStatus.wrong) &&
              p != null &&
              p.isFinite &&
              p >= 0 &&
              p <= 1 &&
              predicted.isBefore(kickoff) &&
              kickoff.isBefore(cutoff) &&
              resolved != null &&
              resolved.isAfter(kickoff) &&
              resolved.isBefore(cutoff);
        }).toList()..sort((a, b) {
          final date = a.firstSeenAt.compareTo(b.firstSeenAt);
          return date != 0 ? date : a.fixtureId.compareTo(b.fixtureId);
        });

    final unique = <int, SmartBetAnalysisRecord>{};
    for (final record in candidates) {
      unique.putIfAbsent(record.fixtureId, () => record);
    }

    if (unique.length < 50) return null;

    // Probabilità di riferimento al centro dell'intervallo:
    // permette di ricavare la correzione senza saturazione
    // ai limiti 0.01 / 0.99.
    final result = const SmartBetHistoricalCalibrationService().evaluate(
      engine: engine,
      market: normalized,
      probability: 0.5,
      asOf: cutoff,
      records: unique.values.toList(),
    );

    if (!result.applied || result.sampleSize != unique.length) {
      return null;
    }

    final correction = result.calibrated - 0.5;

    if (!correction.isFinite ||
        correction.abs() <= 1e-9 ||
        correction.abs() > 0.100000001) {
      return null;
    }

    return SmartBetFrozenModelSnapshot._(
      id: _idFor(engine, normalized, cutoff),
      engine: engine,
      market: normalized,
      frozenAt: cutoff,
      trainingFixtures: unique.length,
      adjustment: correction,
    );
  }

  double calibratedProbability(double original) {
    if (!original.isFinite || original < 0 || original > 1) {
      throw ArgumentError.value(original, 'original');
    }

    return (original + adjustment).clamp(0.01, 0.99).toDouble();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'algorithmVersion': algorithmVersion,
    'engine': engine.name,
    'market': market,
    'frozenAt': frozenAt.toUtc().toIso8601String(),
    'trainingFixtures': trainingFixtures,
    'adjustment': adjustment,
  };

  factory SmartBetFrozenModelSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['algorithmVersion'] != algorithmVersion) {
      throw const FormatException('Versione modello non supportata');
    }

    final engineName = json['engine'] as String;
    final engine = SmartBetAnalysisEngine.values.firstWhere(
      (value) => value.name == engineName,
    );

    final market = json['market'] as String;
    final frozenAt = DateTime.parse(json['frozenAt'] as String).toUtc();
    final fixtures = (json['trainingFixtures'] as num).toInt();
    final adjustment = (json['adjustment'] as num).toDouble();
    final id = json['id'] as String;

    if (market.isEmpty ||
        normalizeAnalysisMarket(market) != market ||
        fixtures < 50 ||
        !adjustment.isFinite ||
        adjustment.abs() <= 1e-9 ||
        adjustment.abs() > 0.100000001 ||
        id != _idFor(engine, market, frozenAt)) {
      throw const FormatException('Snapshot modello non valido');
    }

    return SmartBetFrozenModelSnapshot._(
      id: id,
      engine: engine,
      market: market,
      frozenAt: frozenAt,
      trainingFixtures: fixtures,
      adjustment: adjustment,
    );
  }
}

/// Archivio separato e write-once.
/// Non modifica i record delle analisi esistenti.
class SmartBetFrozenModelSnapshotStore {
  static const storageKey = 'smartbet_frozen_models_v1';

  SharedPreferences? _prefs;
  bool _initialized = false;

  final Map<String, SmartBetFrozenModelSnapshot> _models = {};

  List<SmartBetFrozenModelSnapshot> get snapshots =>
      List.unmodifiable(_models.values);

  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);

    final loaded = <String, SmartBetFrozenModelSnapshot>{};

    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Archivio modelli non valido');
      }

      for (final value in decoded) {
        if (value is! Map) {
          throw const FormatException('Record modello non valido');
        }

        final snapshot = SmartBetFrozenModelSnapshot.fromJson(
          Map<String, dynamic>.from(value),
        );

        if (loaded.containsKey(snapshot.id)) {
          throw StateError('Identificativo modello duplicato');
        }

        loaded[snapshot.id] = snapshot;
      }
    }

    _models.addAll(loaded);
    _initialized = true;
  }

  Future<SmartBetFrozenModelSnapshot> save(
    SmartBetFrozenModelSnapshot snapshot,
  ) async {
    await initialize();

    final existing = _models[snapshot.id];

    if (existing != null) {
      if (jsonEncode(existing.toJson()) != jsonEncode(snapshot.toJson())) {
        throw StateError('Modello già congelato: vietata la sovrascrittura');
      }
      return existing;
    }

    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final next = [..._models.values, snapshot];

    final saved = await prefs.setString(
      storageKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );

    if (!saved) {
      throw StateError('Impossibile salvare il modello congelato');
    }

    _models[snapshot.id] = snapshot;
    return snapshot;
  }
}
