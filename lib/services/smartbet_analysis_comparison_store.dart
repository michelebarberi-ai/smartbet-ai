import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_analysis_history_store.dart';

class SmartBetAnalysisComparisonLink {
  final int fixtureId;

  final String smartBetRecordKey;
  final String diegoRecordKey;

  final String smartBetMarket;
  final String diegoMarket;

  final List<SmartBetAnalysisSource> sources;

  final DateTime firstSeenAt;
  final DateTime lastSeenAt;

  const SmartBetAnalysisComparisonLink({
    required this.fixtureId,
    required this.smartBetRecordKey,
    required this.diegoRecordKey,
    required this.smartBetMarket,
    required this.diegoMarket,
    required this.sources,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  String get key =>
      '$fixtureId|'
      '${normalizeAnalysisMarket(smartBetMarket)}|'
      '${normalizeAnalysisMarket(diegoMarket)}';

  SmartBetAnalysisComparisonLink withSource({
    required SmartBetAnalysisSource source,
    required DateTime seenAt,
  }) {
    final merged = <SmartBetAnalysisSource>{...sources, source}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return SmartBetAnalysisComparisonLink(
      fixtureId: fixtureId,
      smartBetRecordKey: smartBetRecordKey,
      diegoRecordKey: diegoRecordKey,
      smartBetMarket: smartBetMarket,
      diegoMarket: diegoMarket,
      sources: List.unmodifiable(merged),
      firstSeenAt: firstSeenAt,
      lastSeenAt: seenAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fixtureId': fixtureId,
      'smartBetRecordKey': smartBetRecordKey,
      'diegoRecordKey': diegoRecordKey,
      'smartBetMarket': smartBetMarket,
      'diegoMarket': diegoMarket,
      'sources': sources.map((e) => e.name).toList(),
      'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
      'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
    };
  }

  static SmartBetAnalysisComparisonLink? fromJson(Map<String, dynamic> json) {
    final fixtureId = _toInt(json['fixtureId']);

    final firstSeenAt = DateTime.tryParse(
      json['firstSeenAt']?.toString() ?? '',
    );

    final lastSeenAt = DateTime.tryParse(json['lastSeenAt']?.toString() ?? '');

    final smartBetRecordKey = json['smartBetRecordKey']?.toString() ?? '';

    final diegoRecordKey = json['diegoRecordKey']?.toString() ?? '';

    final smartBetMarket = normalizeAnalysisMarket(
      json['smartBetMarket']?.toString() ?? '',
    );

    final diegoMarket = normalizeAnalysisMarket(
      json['diegoMarket']?.toString() ?? '',
    );

    if (fixtureId == null ||
        fixtureId <= 0 ||
        firstSeenAt == null ||
        lastSeenAt == null ||
        smartBetRecordKey.isEmpty ||
        diegoRecordKey.isEmpty ||
        smartBetMarket.isEmpty ||
        diegoMarket.isEmpty) {
      return null;
    }

    final sources = <SmartBetAnalysisSource>[];

    final rawSources = json['sources'];

    if (rawSources is List) {
      for (final raw in rawSources) {
        final source = _sourceFromName(raw?.toString());

        if (source != null && !sources.contains(source)) {
          sources.add(source);
        }
      }
    }

    sources.sort((a, b) => a.index.compareTo(b.index));

    return SmartBetAnalysisComparisonLink(
      fixtureId: fixtureId,
      smartBetRecordKey: smartBetRecordKey,
      diegoRecordKey: diegoRecordKey,
      smartBetMarket: smartBetMarket,
      diegoMarket: diegoMarket,
      sources: List.unmodifiable(sources),
      firstSeenAt: firstSeenAt.toUtc(),
      lastSeenAt: lastSeenAt.toUtc(),
    );
  }
}

class SmartBetAnalysisComparisonStats {
  final int linkedPairs;
  final int comparablePairs;

  final int pendingPairs;
  final int unsupportedPairs;

  final int bothCorrect;
  final int smartBetOnlyCorrect;
  final int diegoOnlyCorrect;
  final int bothWrong;

  const SmartBetAnalysisComparisonStats({
    required this.linkedPairs,
    required this.comparablePairs,
    required this.pendingPairs,
    required this.unsupportedPairs,
    required this.bothCorrect,
    required this.smartBetOnlyCorrect,
    required this.diegoOnlyCorrect,
    required this.bothWrong,
  });

  int get smartBetCorrect => bothCorrect + smartBetOnlyCorrect;

  int get diegoCorrect => bothCorrect + diegoOnlyCorrect;

  double get smartBetAccuracy {
    if (comparablePairs <= 0) {
      return 0.0;
    }

    return smartBetCorrect / comparablePairs * 100.0;
  }

  double get diegoAccuracy {
    if (comparablePairs <= 0) {
      return 0.0;
    }

    return diegoCorrect / comparablePairs * 100.0;
  }
}

class SmartBetAnalysisComparisonStore extends ChangeNotifier {
  SmartBetAnalysisComparisonStore();

  static final SmartBetAnalysisComparisonStore instance =
      SmartBetAnalysisComparisonStore();

  static const String _storageKey = 'smartbet_analysis_comparison_links_v1';

  SharedPreferences? _preferences;

  bool _initialized = false;

  final List<SmartBetAnalysisComparisonLink> _links = [];

  bool get initialized => _initialized;

  List<SmartBetAnalysisComparisonLink> get links {
    final result = List<SmartBetAnalysisComparisonLink>.from(_links);

    result.sort((a, b) => b.firstSeenAt.compareTo(a.firstSeenAt));

    return List.unmodifiable(result);
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

  Future<SmartBetAnalysisComparisonLink?> registerPair({
    required SmartBetAnalysisRecord smartBet,
    required SmartBetAnalysisRecord diego,
    required SmartBetAnalysisSource source,
    DateTime? recordedAt,
  }) async {
    await initialize();

    if (smartBet.engine != SmartBetAnalysisEngine.smartBet ||
        diego.engine != SmartBetAnalysisEngine.diego) {
      return null;
    }

    if (smartBet.fixtureId <= 0 || smartBet.fixtureId != diego.fixtureId) {
      return null;
    }

    final smartMarket = normalizeAnalysisMarket(smartBet.market);

    final diegoMarket = normalizeAnalysisMarket(diego.market);

    if (smartMarket.isEmpty || diegoMarket.isEmpty) {
      return null;
    }

    final now = (recordedAt ?? DateTime.now()).toUtc();

    final key =
        '${smartBet.fixtureId}|'
        '$smartMarket|'
        '$diegoMarket';

    final existingIndex = _links.indexWhere((link) => link.key == key);

    if (existingIndex >= 0) {
      final updated = _links[existingIndex].withSource(
        source: source,
        seenAt: now,
      );

      _links[existingIndex] = updated;

      await _save();

      notifyListeners();

      return updated;
    }

    final link = SmartBetAnalysisComparisonLink(
      fixtureId: smartBet.fixtureId,
      smartBetRecordKey: smartBet.key,
      diegoRecordKey: diego.key,
      smartBetMarket: smartMarket,
      diegoMarket: diegoMarket,
      sources: List.unmodifiable([source]),
      firstSeenAt: now,
      lastSeenAt: now,
    );

    _links.add(link);

    await _save();

    notifyListeners();

    return link;
  }

  SmartBetAnalysisComparisonStats calculateStats({
    required List<SmartBetAnalysisRecord> analysisRecords,
    bool prospectiveOnly = true,
  }) {
    final byKey = <String, SmartBetAnalysisRecord>{
      for (final record in analysisRecords) record.key: record,
    };

    var linkedPairs = 0;
    var comparablePairs = 0;

    var pendingPairs = 0;
    var unsupportedPairs = 0;

    var bothCorrect = 0;
    var smartBetOnlyCorrect = 0;
    var diegoOnlyCorrect = 0;
    var bothWrong = 0;

    for (final link in _links) {
      final smartBet = byKey[link.smartBetRecordKey];

      final diego = byKey[link.diegoRecordKey];

      if (smartBet == null || diego == null) {
        continue;
      }

      if (prospectiveOnly &&
          (!smartBet.prospectiveEligible || !diego.prospectiveEligible)) {
        continue;
      }

      linkedPairs++;

      final smartStatus = smartBet.status;
      final diegoStatus = diego.status;

      if (smartStatus == SmartBetAnalysisStatus.pending ||
          diegoStatus == SmartBetAnalysisStatus.pending) {
        pendingPairs++;
        continue;
      }

      if (smartStatus == SmartBetAnalysisStatus.unsupported ||
          diegoStatus == SmartBetAnalysisStatus.unsupported) {
        unsupportedPairs++;
        continue;
      }

      final smartCorrect = smartStatus == SmartBetAnalysisStatus.correct;

      final diegoCorrect = diegoStatus == SmartBetAnalysisStatus.correct;

      comparablePairs++;

      if (smartCorrect && diegoCorrect) {
        bothCorrect++;
      } else if (smartCorrect) {
        smartBetOnlyCorrect++;
      } else if (diegoCorrect) {
        diegoOnlyCorrect++;
      } else {
        bothWrong++;
      }
    }

    return SmartBetAnalysisComparisonStats(
      linkedPairs: linkedPairs,
      comparablePairs: comparablePairs,
      pendingPairs: pendingPairs,
      unsupportedPairs: unsupportedPairs,
      bothCorrect: bothCorrect,
      smartBetOnlyCorrect: smartBetOnlyCorrect,
      diegoOnlyCorrect: diegoOnlyCorrect,
      bothWrong: bothWrong,
    );
  }

  Future<void> clear() async {
    await initialize();

    _links.clear();

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

      _links.clear();

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final link = SmartBetAnalysisComparisonLink.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (link != null) {
          _links.add(link);
        }
      }
    } catch (e) {
      debugPrint('SmartBet comparison store load error: $e');
    }
  }

  Future<void> _save() async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();

    try {
      await prefs.setString(
        _storageKey,
        jsonEncode(_links.map((link) => link.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('SmartBet comparison store save error: $e');
    }
  }
}

SmartBetAnalysisSource? _sourceFromName(String? value) {
  for (final source in SmartBetAnalysisSource.values) {
    if (source.name == value) {
      return source;
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
