import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prediction_store.dart';

class SavedPredictionStore extends ChangeNotifier {
  SavedPredictionStore._();

  static final SavedPredictionStore instance = SavedPredictionStore._();

  static const String _storageKey = 'smartbet_saved_predictions_v1';

  final List<SavedPrediction> _items = [];

  bool _initialized = false;

  bool get initialized => _initialized;

  List<SavedPrediction> get items {
    final result = List<SavedPrediction>.from(_items);

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return List.unmodifiable(result);
  }

  int get count => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool isSaved(int fixtureId) {
    return _items.any((item) => item.fixtureId == fixtureId);
  }

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await _load();

    _initialized = true;

    notifyListeners();
  }

  // ============================================================
  // SAVE / REMOVE
  // ============================================================

  Future<void> toggle(SavedPrediction prediction) async {
    final index = _items.indexWhere(
      (item) => item.fixtureId == prediction.fixtureId,
    );

    if (index >= 0) {
      _items.removeAt(index);
    } else {
      _items.add(prediction);
    }

    await _save();

    notifyListeners();
  }

  Future<void> add(SavedPrediction prediction) async {
    final index = _items.indexWhere(
      (item) => item.fixtureId == prediction.fixtureId,
    );

    if (index >= 0) {
      _items[index] = prediction;
    } else {
      _items.add(prediction);
    }

    await _save();

    notifyListeners();
  }

  Future<void> remove(int fixtureId) async {
    _items.removeWhere((item) => item.fixtureId == fixtureId);

    await _save();

    notifyListeners();
  }

  Future<void> clear() async {
    _items.clear();

    await _save();

    notifyListeners();
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _load() async {
    try {
      final prefs = SharedPreferencesAsync();

      final raw = await prefs.getString(_storageKey);

      if (raw == null || raw.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return;
      }

      _items.clear();

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final map = Map<String, dynamic>.from(item);

        final parsed = _fromJson(map);

        if (parsed != null) {
          _items.add(parsed);
        }
      }
    } catch (e) {
      debugPrint('SavedPredictionStore load error: $e');
    }
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _save() async {
    try {
      final prefs = SharedPreferencesAsync();

      final data = _items.map(_toJson).toList();

      await prefs.setString(_storageKey, jsonEncode(data));
    } catch (e) {
      debugPrint('SavedPredictionStore save error: $e');
    }
  }

  // ============================================================
  // JSON
  // ============================================================

  Map<String, dynamic> _toJson(SavedPrediction item) {
    return {
      'fixtureId': item.fixtureId,
      'matchLabel': item.matchLabel,
      'league': item.league,
      'matchDate': item.matchDate.toIso8601String(),
      'smartScore': item.smartScore,
      'homeProbability': item.homeProbability,
      'drawProbability': item.drawProbability,
      'awayProbability': item.awayProbability,
      'prediction': item.prediction,
      'valueBet': item.valueBet,
      'risk': item.risk,
      'shouldBet': item.shouldBet,
      'recommendedStakePercent': item.recommendedStakePercent,
      'stakeOutcome': item.stakeOutcome,
      'stakeOdd': item.stakeOdd,
      'stakeBookmaker': item.stakeBookmaker,
      'stakeRecommendation': item.stakeRecommendation,
      'createdAt': item.createdAt.toIso8601String(),
    };
  }

  SavedPrediction? _fromJson(Map<String, dynamic> json) {
    try {
      return SavedPrediction(
        fixtureId: _toInt(json['fixtureId']),

        matchLabel: json['matchLabel']?.toString() ?? '',

        league: json['league']?.toString() ?? '',

        matchDate:
            DateTime.tryParse(json['matchDate']?.toString() ?? '') ??
            DateTime.now(),

        smartScore: _toInt(json['smartScore']),

        homeProbability: _toInt(json['homeProbability']),

        drawProbability: _toInt(json['drawProbability']),

        awayProbability: _toInt(json['awayProbability']),

        prediction: json['prediction']?.toString() ?? 'N/D',

        valueBet: json['valueBet']?.toString() ?? '',

        risk: json['risk']?.toString() ?? '',

        shouldBet: json['shouldBet'] == true,

        recommendedStakePercent: _toDouble(json['recommendedStakePercent']),

        stakeOutcome: json['stakeOutcome']?.toString() ?? '',

        stakeOdd: _toDouble(json['stakeOdd']),

        stakeBookmaker: json['stakeBookmaker']?.toString() ?? '',

        stakeRecommendation: json['stakeRecommendation']?.toString() ?? '',

        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
