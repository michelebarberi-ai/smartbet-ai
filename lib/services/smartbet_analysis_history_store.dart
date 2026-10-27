import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_analysis_market_settlement.dart';

enum SmartBetAnalysisEngine { smartBet, diego }

enum SmartBetAnalysisSource { analysis, aiCoupon, combinations, dailyResults }

enum SmartBetAnalysisStatus { pending, correct, wrong, unsupported }

class SmartBetAnalysisRecord {
  final SmartBetAnalysisEngine engine;

  final int fixtureId;
  final String homeTeam;
  final String awayTeam;
  final String league;
  final String country;
  final DateTime matchDate;

  final String market;
  final double? probability;

  /// Solo SmartBet.
  final int? smartScore;

  /// Solo Diego.
  final int? confidence;
  final String? classification;
  final bool? qualified;

  final List<SmartBetAnalysisSource> sources;

  /// True solo quando la previsione è stata registrata
  /// prima dell'inizio della partita.
  final bool prospectiveEligible;

  final SmartBetAnalysisStatus status;

  final int? actualHomeGoals;
  final int? actualAwayGoals;

  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final DateTime? resolvedAt;

  const SmartBetAnalysisRecord({
    required this.engine,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    required this.country,
    required this.matchDate,
    required this.market,
    required this.probability,
    required this.smartScore,
    required this.confidence,
    required this.classification,
    required this.qualified,
    required this.sources,
    required this.prospectiveEligible,
    required this.status,
    required this.actualHomeGoals,
    required this.actualAwayGoals,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.resolvedAt,
  });

  String get key =>
      '${engine.name}|$fixtureId|${normalizeAnalysisMarket(market)}';

  String get matchLabel => '$homeTeam - $awayTeam';

  bool get hasActualResult =>
      actualHomeGoals != null && actualAwayGoals != null;

  SmartBetAnalysisRecord withSource({
    required SmartBetAnalysisSource source,
    required DateTime seenAt,
  }) {
    final mergedSources = <SmartBetAnalysisSource>{...sources, source}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      league: league,
      country: country,
      matchDate: matchDate,
      market: market,
      probability: probability,
      smartScore: smartScore,
      confidence: confidence,
      classification: classification,
      qualified: qualified,
      sources: List.unmodifiable(mergedSources),
      prospectiveEligible: prospectiveEligible,
      status: status,
      actualHomeGoals: actualHomeGoals,
      actualAwayGoals: actualAwayGoals,
      firstSeenAt: firstSeenAt,
      lastSeenAt: seenAt,
      resolvedAt: resolvedAt,
    );
  }

  SmartBetAnalysisRecord withActualResult({
    required int homeGoals,
    required int awayGoals,
    required SmartBetAnalysisStatus status,
    required DateTime updatedAt,
  }) {
    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      league: league,
      country: country,
      matchDate: matchDate,
      market: market,
      probability: probability,
      smartScore: smartScore,
      confidence: confidence,
      classification: classification,
      qualified: qualified,
      sources: sources,
      prospectiveEligible: prospectiveEligible,
      status: status,
      actualHomeGoals: homeGoals,
      actualAwayGoals: awayGoals,
      firstSeenAt: firstSeenAt,
      lastSeenAt: updatedAt,
      resolvedAt:
          resolvedAt ??
          (this.status == SmartBetAnalysisStatus.pending
              ? updatedAt.toUtc()
              : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'engine': engine.name,
      'fixtureId': fixtureId,
      'homeTeam': homeTeam,
      'awayTeam': awayTeam,
      'league': league,
      'country': country,
      'matchDate': matchDate.toUtc().toIso8601String(),
      'market': market,
      'probability': probability,
      'smartScore': smartScore,
      'confidence': confidence,
      'classification': classification,
      'qualified': qualified,
      'sources': sources.map((source) => source.name).toList(),
      'prospectiveEligible': prospectiveEligible,
      'status': status.name,
      'actualHomeGoals': actualHomeGoals,
      'actualAwayGoals': actualAwayGoals,
      'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
      'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
      'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
    };
  }

  static SmartBetAnalysisRecord? fromJson(Map<String, dynamic> json) {
    final fixtureId = _toInt(json['fixtureId']);

    final engine = _analysisEngineFromName(json['engine']?.toString());

    final matchDate = DateTime.tryParse(json['matchDate']?.toString() ?? '');

    final firstSeenAt = DateTime.tryParse(
      json['firstSeenAt']?.toString() ?? '',
    );

    final lastSeenAt = DateTime.tryParse(json['lastSeenAt']?.toString() ?? '');
    final resolvedAt = DateTime.tryParse(json['resolvedAt']?.toString() ?? '');

    final market = normalizeAnalysisMarket(json['market']?.toString() ?? '');

    if (fixtureId == null ||
        fixtureId <= 0 ||
        engine == null ||
        matchDate == null ||
        firstSeenAt == null ||
        lastSeenAt == null ||
        market.isEmpty) {
      return null;
    }

    final rawSources = json['sources'];

    final sources = <SmartBetAnalysisSource>[];

    if (rawSources is List) {
      for (final raw in rawSources) {
        final source = _analysisSourceFromName(raw?.toString());

        if (source != null && !sources.contains(source)) {
          sources.add(source);
        }
      }
    }

    sources.sort((a, b) => a.index.compareTo(b.index));

    final status =
        _analysisStatusFromName(json['status']?.toString()) ??
        SmartBetAnalysisStatus.pending;

    return SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId,
      homeTeam: json['homeTeam']?.toString() ?? '',
      awayTeam: json['awayTeam']?.toString() ?? '',
      league: json['league']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      matchDate: matchDate.toUtc(),
      market: market,
      probability: _toDouble(json['probability']),
      smartScore: _toInt(json['smartScore']),
      confidence: _toInt(json['confidence']),
      classification: json['classification']?.toString(),
      qualified: _toBool(json['qualified']),
      sources: List.unmodifiable(sources),
      prospectiveEligible: _toBool(json['prospectiveEligible']) ?? false,
      status: status,
      actualHomeGoals: _toInt(json['actualHomeGoals']),
      actualAwayGoals: _toInt(json['actualAwayGoals']),
      firstSeenAt: firstSeenAt.toUtc(),
      lastSeenAt: lastSeenAt.toUtc(),
      resolvedAt: resolvedAt?.toUtc(),
    );
  }
}

class SmartBetAnalysisEngineStats {
  final int analyzed;
  final int correct;
  final int wrong;
  final int pending;
  final int unsupported;

  const SmartBetAnalysisEngineStats({
    required this.analyzed,
    required this.correct,
    required this.wrong,
    required this.pending,
    required this.unsupported,
  });

  int get settled => correct + wrong;

  double get accuracy {
    if (settled <= 0) {
      return 0.0;
    }

    return correct / settled * 100.0;
  }
}

class SmartBetAnalysisHistoryStore extends ChangeNotifier {
  SmartBetAnalysisHistoryStore();

  static final SmartBetAnalysisHistoryStore instance =
      SmartBetAnalysisHistoryStore();

  static const String _storageKey = 'smartbet_analysis_history_v1';

  SharedPreferences? _preferences;

  bool _initialized = false;

  final List<SmartBetAnalysisRecord> _records = [];

  bool get initialized => _initialized;

  List<SmartBetAnalysisRecord> get records {
    final values = List<SmartBetAnalysisRecord>.from(_records);

    values.sort((a, b) => b.firstSeenAt.compareTo(a.firstSeenAt));

    return List.unmodifiable(values);
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

  Future<SmartBetAnalysisRecord?> registerAnalysis({
    required SmartBetAnalysisEngine engine,
    required SmartBetAnalysisSource source,
    required int fixtureId,
    required String homeTeam,
    required String awayTeam,
    required String league,
    required String country,
    required DateTime matchDate,
    required String market,
    double? probability,
    int? smartScore,
    int? confidence,
    String? classification,
    bool? qualified,
    DateTime? recordedAt,
  }) async {
    await initialize();

    if (fixtureId <= 0) {
      return null;
    }

    final normalizedMarket = normalizeAnalysisMarket(market);

    if (normalizedMarket.isEmpty || normalizedMarket == 'N/D') {
      return null;
    }

    final now = (recordedAt ?? DateTime.now()).toUtc();
    final normalizedMatchDate = matchDate.toUtc();

    final key = '${engine.name}|$fixtureId|$normalizedMarket';

    final existingIndex = _records.indexWhere((record) => record.key == key);

    // ============================================================
    // DEDUP
    //
    // La prima previsione resta immutabile.
    // Se la stessa selezione viene trovata da più funzioni,
    // aggiungiamo soltanto la nuova source.
    // ============================================================

    if (existingIndex >= 0) {
      final updated = _records[existingIndex].withSource(
        source: source,
        seenAt: now,
      );

      _records[existingIndex] = updated;

      await _save();

      notifyListeners();

      return updated;
    }

    final record = SmartBetAnalysisRecord(
      engine: engine,
      fixtureId: fixtureId,
      homeTeam: homeTeam.trim(),
      awayTeam: awayTeam.trim(),
      league: league.trim(),
      country: country.trim(),
      matchDate: normalizedMatchDate,
      market: normalizedMarket,
      probability: _normalizeProbability(probability),
      smartScore: smartScore,
      confidence: confidence,
      classification: classification?.trim(),
      qualified: qualified,
      sources: List.unmodifiable([source]),
      prospectiveEligible: now.isBefore(normalizedMatchDate),
      status: SmartBetAnalysisStatus.pending,
      actualHomeGoals: null,
      actualAwayGoals: null,
      firstSeenAt: now,
      lastSeenAt: now,
    );

    _records.add(record);

    await _save();

    notifyListeners();

    return record;
  }

  Future<int> registerActualResult({
    required int fixtureId,
    required int homeGoals,
    required int awayGoals,
    DateTime? updatedAt,
  }) async {
    await initialize();

    if (fixtureId <= 0 || homeGoals < 0 || awayGoals < 0) {
      return 0;
    }

    final now = (updatedAt ?? DateTime.now()).toUtc();

    var updatedRecords = 0;

    for (var index = 0; index < _records.length; index++) {
      final record = _records[index];

      if (record.fixtureId != fixtureId) {
        continue;
      }

      final settlement = SmartBetAnalysisMarketSettlement.evaluate(
        market: record.market,
        homeGoals: homeGoals,
        awayGoals: awayGoals,
      );

      final status = switch (settlement) {
        SmartBetAnalysisSettlement.correct => SmartBetAnalysisStatus.correct,
        SmartBetAnalysisSettlement.wrong => SmartBetAnalysisStatus.wrong,
        SmartBetAnalysisSettlement.unsupported =>
          SmartBetAnalysisStatus.unsupported,
      };

      _records[index] = record.withActualResult(
        homeGoals: homeGoals,
        awayGoals: awayGoals,
        status: status,
        updatedAt: now,
      );

      updatedRecords++;
    }

    if (updatedRecords > 0) {
      await _save();

      notifyListeners();
    }

    return updatedRecords;
  }

  SmartBetAnalysisEngineStats statsFor(
    SmartBetAnalysisEngine engine, {
    bool prospectiveOnly = true,
  }) {
    final engineRecords = _records
        .where((record) {
          if (record.engine != engine) {
            return false;
          }

          if (prospectiveOnly && !record.prospectiveEligible) {
            return false;
          }

          return true;
        })
        .toList(growable: false);

    var correct = 0;
    var wrong = 0;
    var pending = 0;
    var unsupported = 0;

    for (final record in engineRecords) {
      switch (record.status) {
        case SmartBetAnalysisStatus.correct:
          correct++;

        case SmartBetAnalysisStatus.wrong:
          wrong++;

        case SmartBetAnalysisStatus.pending:
          pending++;

        case SmartBetAnalysisStatus.unsupported:
          unsupported++;
      }
    }

    return SmartBetAnalysisEngineStats(
      analyzed: engineRecords.length,
      correct: correct,
      wrong: wrong,
      pending: pending,
      unsupported: unsupported,
    );
  }

  List<SmartBetAnalysisRecord> recordsForFixture(int fixtureId) {
    return List.unmodifiable(
      _records.where((record) => record.fixtureId == fixtureId),
    );
  }

  Future<void> clear() async {
    await initialize();

    _records.clear();

    await _save();

    notifyListeners();
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

      _records.clear();

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final record = SmartBetAnalysisRecord.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (record != null) {
          _records.add(record);
        }
      }
    } catch (error) {
      debugPrint('SmartBet analysis history load error: $error');
    }
  }

  Future<void> _save() async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();

    try {
      final encoded = jsonEncode(
        _records.map((record) => record.toJson()).toList(),
      );

      await prefs.setString(_storageKey, encoded);
    } catch (error) {
      debugPrint('SmartBet analysis history save error: $error');
    }
  }
}

String normalizeAnalysisMarket(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}

double? _normalizeProbability(double? probability) {
  if (probability == null || !probability.isFinite) {
    return null;
  }

  return probability.clamp(0.0, 1.0).toDouble();
}

SmartBetAnalysisEngine? _analysisEngineFromName(String? value) {
  for (final engine in SmartBetAnalysisEngine.values) {
    if (engine.name == value) {
      return engine;
    }
  }

  return null;
}

SmartBetAnalysisSource? _analysisSourceFromName(String? value) {
  for (final source in SmartBetAnalysisSource.values) {
    if (source.name == value) {
      return source;
    }
  }

  return null;
}

SmartBetAnalysisStatus? _analysisStatusFromName(String? value) {
  for (final status in SmartBetAnalysisStatus.values) {
    if (status.name == value) {
      return status;
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
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '');
}

bool? _toBool(dynamic value) {
  if (value is bool) {
    return value;
  }

  final normalized = value?.toString().trim().toLowerCase();

  if (normalized == 'true') {
    return true;
  }

  if (normalized == 'false') {
    return false;
  }

  return null;
}
