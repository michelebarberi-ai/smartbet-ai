import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';

class GoalVdLineComparisonRecord {
  final int fixtureId;

  final String matchLabel;
  final String league;
  final DateTime matchDate;

  final Map<String, dynamic>? smartBet;
  final Map<String, dynamic>? shadow;
  final Map<String, dynamic>? actualResult;

  final DateTime createdAt;
  final DateTime updatedAt;

  const GoalVdLineComparisonRecord({
    required this.fixtureId,
    required this.matchLabel,
    required this.league,
    required this.matchDate,
    required this.smartBet,
    required this.shadow,
    required this.actualResult,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasSmartBet => smartBet != null;

  bool get hasShadow => shadow != null;

  bool get isComplete => hasSmartBet && hasShadow;

  bool get hasActualResult => actualResult != null;

  GoalVdLineComparisonRecord copyWith({
    String? matchLabel,
    String? league,
    DateTime? matchDate,
    Map<String, dynamic>? smartBet,
    Map<String, dynamic>? shadow,
    Map<String, dynamic>? actualResult,
    DateTime? updatedAt,
  }) {
    return GoalVdLineComparisonRecord(
      fixtureId: fixtureId,
      matchLabel: matchLabel ?? this.matchLabel,
      league: league ?? this.league,
      matchDate: matchDate ?? this.matchDate,
      smartBet: smartBet ?? this.smartBet,
      shadow: shadow ?? this.shadow,
      actualResult: actualResult ?? this.actualResult,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fixtureId': fixtureId,
      'matchLabel': matchLabel,
      'league': league,
      'matchDate': matchDate.toIso8601String(),
      'smartBet': smartBet,
      'shadow': shadow,
      'actualResult': actualResult,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static GoalVdLineComparisonRecord? fromJson(Map<String, dynamic> json) {
    try {
      final fixtureId = _toInt(json['fixtureId']);

      if (fixtureId <= 0) {
        return null;
      }

      final now = DateTime.now();

      return GoalVdLineComparisonRecord(
        fixtureId: fixtureId,
        matchLabel: json['matchLabel']?.toString() ?? '',
        league: json['league']?.toString() ?? '',
        matchDate:
            DateTime.tryParse(json['matchDate']?.toString() ?? '') ?? now,
        smartBet: _toMap(json['smartBet']),
        shadow: _toMap(json['shadow']),
        actualResult: _toMap(json['actualResult']),
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
        updatedAt:
            DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _toMap(dynamic value) {
    if (value is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(value);
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class GoalVdLineComparisonStore {
  GoalVdLineComparisonStore._();

  static final GoalVdLineComparisonStore instance =
      GoalVdLineComparisonStore._();

  static const String _storageKey = 'goalvdline_shadow_comparison_v1';

  final Map<int, GoalVdLineComparisonRecord> _records =
      <int, GoalVdLineComparisonRecord>{};

  bool _loaded = false;

  Future<void> _queue = Future<void>.value();

  // ============================================================
  // SMARTBET
  // ============================================================

  void registerSmartBet({
    required MatchModel match,
    required AnalysisResult result,
  }) {
    _enqueue(() async {
      await _ensureLoaded();

      final now = DateTime.now();

      final record = _baseRecord(match: match, now: now).copyWith(
        smartBet: {
          'prediction': result.prediction,
          'smartScore': result.smartScore,
          'homeProbability': result.homeProbability,
          'drawProbability': result.drawProbability,
          'awayProbability': result.awayProbability,
          'over15Probability': result.over15Probability,
          'under15Probability': result.under15Probability,
          'over25Probability': result.over25Probability,
          'under25Probability': result.under25Probability,
          'goalProbability': result.goalProbability,
          'noGoalProbability': result.noGoalProbability,
          'expectedHomeGoals': result.expectedHomeGoals,
          'expectedAwayGoals': result.expectedAwayGoals,
          'risk': result.risk,
          'shouldBet': result.shouldBet,
          'capturedAt': now.toIso8601String(),
        },
        updatedAt: now,
      );

      _records[match.fixtureId] = record;

      await _save();
    });
  }

  // ============================================================
  // GOALVDLINE SHADOW
  // ============================================================

  void registerShadow({
    required MatchModel match,
    required Map<String, dynamic> shadow,
  }) {
    _enqueue(() async {
      await _ensureLoaded();

      final now = DateTime.now();

      final record = _baseRecord(
        match: match,
        now: now,
      ).copyWith(shadow: Map<String, dynamic>.from(shadow), updatedAt: now);

      _records[match.fixtureId] = record;

      await _save();
    });
  }

  // ============================================================
  // RISULTATO REALE
  // ============================================================

  void registerActualResult({
    required int fixtureId,
    required int homeGoals,
    required int awayGoals,
  }) {
    _enqueue(() async {
      await _ensureLoaded();

      final existing = _records[fixtureId];

      if (existing == null) {
        return;
      }

      final outcome = homeGoals > awayGoals
          ? '1'
          : homeGoals < awayGoals
          ? '2'
          : 'X';

      final now = DateTime.now();

      _records[fixtureId] = existing.copyWith(
        actualResult: {
          'homeGoals': homeGoals,
          'awayGoals': awayGoals,
          'outcome': outcome,
          'resolvedAt': now.toIso8601String(),
        },
        updatedAt: now,
      );

      await _save();
    });
  }

  // ============================================================
  // READ
  // ============================================================

  Future<List<GoalVdLineComparisonRecord>> readAll() async {
    await _queue;
    await _ensureLoaded();

    final result = _records.values.toList()
      ..sort((a, b) => b.matchDate.compareTo(a.matchDate));

    return List<GoalVdLineComparisonRecord>.unmodifiable(result);
  }

  Future<GoalVdLineComparisonRecord?> readFixture(int fixtureId) async {
    await _queue;
    await _ensureLoaded();

    return _records[fixtureId];
  }

  // ============================================================
  // SERIAL QUEUE
  // ============================================================

  void _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) async {
      try {
        await action();
      } catch (error, stackTrace) {
        debugPrint('GoalVdLineComparisonStore error: $error');

        debugPrint(stackTrace.toString());
      }
    });
  }

  // ============================================================
  // BASE RECORD / MERGE
  // ============================================================

  GoalVdLineComparisonRecord _baseRecord({
    required MatchModel match,
    required DateTime now,
  }) {
    DateTime matchDate;

    try {
      matchDate = DateTime.parse(match.date).toLocal();
    } catch (_) {
      matchDate = now;
    }

    final existing = _records[match.fixtureId];

    if (existing != null) {
      return existing.copyWith(
        matchLabel: '${match.homeTeam} - ${match.awayTeam}',
        league: match.league,
        matchDate: matchDate,
        updatedAt: now,
      );
    }

    return GoalVdLineComparisonRecord(
      fixtureId: match.fixtureId,
      matchLabel: '${match.homeTeam} - ${match.awayTeam}',
      league: match.league,
      matchDate: matchDate,
      smartBet: null,
      shadow: null,
      actualResult: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }

    final prefs = SharedPreferencesAsync();

    final raw = await prefs.getString(_storageKey);

    _records.clear();

    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) {
            continue;
          }

          final record = GoalVdLineComparisonRecord.fromJson(
            Map<String, dynamic>.from(item),
          );

          if (record != null) {
            _records[record.fixtureId] = record;
          }
        }
      }
    }

    _loaded = true;
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _save() async {
    final prefs = SharedPreferencesAsync();

    final items = _records.values.toList()
      ..sort((a, b) => a.fixtureId.compareTo(b.fixtureId));

    await prefs.setString(
      _storageKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}
