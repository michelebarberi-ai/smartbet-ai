import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_result.dart';

class SmartBetAnalysisCache {
  SmartBetAnalysisCache({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static final SmartBetAnalysisCache instance = SmartBetAnalysisCache();

  static const String _storageKey = 'smartbet_analysis_cache_v1';

  static const Duration defaultMaxAge = Duration(minutes: 20);

  static const int _maxEntries = 128;

  final SharedPreferencesAsync _preferences;

  final Map<int, _SmartBetCacheEntry> _entries = <int, _SmartBetCacheEntry>{};

  bool _loaded = false;

  Future<void> _queue = Future<void>.value();

  Future<AnalysisResult?> read(
    int fixtureId, {
    Duration maxAge = defaultMaxAge,
    DateTime? now,
  }) async {
    await _queue;
    await _ensureLoaded();

    final entry = _entries[fixtureId];

    if (entry == null) {
      return null;
    }

    final reference = now ?? DateTime.now();

    final age = reference.difference(entry.capturedAt);

    if (age.isNegative || age > maxAge) {
      return null;
    }

    return entry.result;
  }

  Future<void> write(int fixtureId, AnalysisResult result, {DateTime? now}) {
    return _enqueue(() async {
      await _ensureLoaded();

      if (fixtureId <= 0 || result.smartScore <= 0) {
        return;
      }

      _entries[fixtureId] = _SmartBetCacheEntry(
        capturedAt: now ?? DateTime.now(),
        result: result,
      );

      _trimToCapacity();

      await _save();
    });
  }

  Future<void> remove(int fixtureId) {
    return _enqueue(() async {
      await _ensureLoaded();

      if (_entries.remove(fixtureId) != null) {
        await _save();
      }
    });
  }

  Future<void> clear() {
    return _enqueue(() async {
      await _ensureLoaded();

      _entries.clear();

      await _preferences.remove(_storageKey);
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }

    _loaded = true;

    final raw = await _preferences.getString(_storageKey);

    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return;
      }

      for (final entry in decoded.entries) {
        final fixtureId = int.tryParse(entry.key.toString());

        if (fixtureId == null || fixtureId <= 0 || entry.value is! Map) {
          continue;
        }

        final cached = _SmartBetCacheEntry.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );

        if (cached != null) {
          _entries[fixtureId] = cached;
        }
      }

      if (_trimToCapacity()) {
        await _save();
      }
    } catch (_) {
      _entries.clear();
    }
  }

  bool _trimToCapacity() {
    if (_entries.length <= _maxEntries) {
      return false;
    }

    final ordered = _entries.entries.toList()
      ..sort((a, b) => b.value.capturedAt.compareTo(a.value.capturedAt));

    final keep = ordered.take(_maxEntries).map((entry) => entry.key).toSet();

    _entries.removeWhere((fixtureId, _) => !keep.contains(fixtureId));

    return true;
  }

  Future<void> _save() async {
    final data = <String, dynamic>{};

    for (final entry in _entries.entries) {
      data[entry.key.toString()] = entry.value.toJson();
    }

    await _preferences.setString(_storageKey, jsonEncode(data));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());

    _queue = next.catchError((_) {});

    return next;
  }
}

class _SmartBetCacheEntry {
  final DateTime capturedAt;
  final AnalysisResult result;

  const _SmartBetCacheEntry({required this.capturedAt, required this.result});

  Map<String, dynamic> toJson() {
    return {
      'capturedAt': capturedAt.toIso8601String(),
      'result': _resultToJson(result),
    };
  }

  static _SmartBetCacheEntry? fromJson(Map<String, dynamic> json) {
    try {
      final capturedAt = DateTime.tryParse(
        json['capturedAt']?.toString() ?? '',
      );

      final resultRaw = json['result'];

      if (capturedAt == null || resultRaw is! Map) {
        return null;
      }

      return _SmartBetCacheEntry(
        capturedAt: capturedAt,
        result: _resultFromJson(Map<String, dynamic>.from(resultRaw)),
      );
    } catch (_) {
      return null;
    }
  }
}

Map<String, dynamic> _resultToJson(AnalysisResult result) {
  return {
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
    'prediction': result.prediction,
    'valueBet': result.valueBet,
    'risk': result.risk,
    'shouldBet': result.shouldBet,
    'recommendedStakePercent': result.recommendedStakePercent,
    'recommendedStakeUnits': result.recommendedStakeUnits,
    'stakeOutcome': result.stakeOutcome,
    'stakeOdd': result.stakeOdd,
    'stakeBookmaker': result.stakeBookmaker,
    'stakeRecommendation': result.stakeRecommendation,
    'recommendedStakeAmount': result.recommendedStakeAmount,
    'explanation': result.explanation,
  };
}

AnalysisResult _resultFromJson(Map<String, dynamic> json) {
  return AnalysisResult(
    smartScore: _toInt(json['smartScore']),
    homeProbability: _toInt(json['homeProbability']),
    drawProbability: _toInt(json['drawProbability']),
    awayProbability: _toInt(json['awayProbability']),
    over15Probability: _toInt(json['over15Probability']),
    under15Probability: _toInt(json['under15Probability']),
    over25Probability: _toInt(json['over25Probability']),
    under25Probability: _toInt(json['under25Probability']),
    goalProbability: _toInt(json['goalProbability']),
    noGoalProbability: _toInt(json['noGoalProbability']),
    expectedHomeGoals: _toDouble(json['expectedHomeGoals']),
    expectedAwayGoals: _toDouble(json['expectedAwayGoals']),
    prediction: json['prediction']?.toString() ?? '',
    valueBet: json['valueBet']?.toString() ?? '',
    risk: json['risk']?.toString() ?? '',
    shouldBet: _toBool(json['shouldBet']),
    recommendedStakePercent: _toDouble(json['recommendedStakePercent']),
    recommendedStakeUnits: _toDouble(json['recommendedStakeUnits']),
    stakeOutcome: json['stakeOutcome']?.toString() ?? '',
    stakeOdd: _toDouble(json['stakeOdd']),
    stakeBookmaker: json['stakeBookmaker']?.toString() ?? '',
    stakeRecommendation:
        json['stakeRecommendation']?.toString() ?? 'Nessuna puntata.',
    recommendedStakeAmount: _toDouble(json['recommendedStakeAmount']),
    explanation: json['explanation']?.toString() ?? '',
  );
}

int _toInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

bool _toBool(dynamic value) {
  if (value is bool) {
    return value;
  }

  return value?.toString().toLowerCase() == 'true';
}
