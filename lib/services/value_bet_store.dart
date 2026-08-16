import 'package:flutter/foundation.dart';

class SavedValueBet {
  final int fixtureId;

  final String matchLabel;

  final String league;

  final DateTime matchDate;

  final String outcome;

  final double odd;

  final String bookmaker;

  final double aiProbability;

  final double marketProbability;

  final double edge;

  final double expectedValue;

  final double fairOdd;

  final String classification;

  final int aiConfidence;

  final int dossierConfidence;

  final bool shouldBet;

  final double stakePercent;

  final DateTime createdAt;

  const SavedValueBet({
    required this.fixtureId,
    required this.matchLabel,
    required this.league,
    required this.matchDate,
    required this.outcome,
    required this.odd,
    required this.bookmaker,
    required this.aiProbability,
    required this.marketProbability,
    required this.edge,
    required this.expectedValue,
    required this.fairOdd,
    required this.classification,
    required this.aiConfidence,
    required this.dossierConfidence,
    required this.shouldBet,
    required this.stakePercent,
    required this.createdAt,
  });

  bool get isStrongValue {
    return classification == 'STRONG VALUE';
  }

  bool get isValue {
    return classification == 'VALUE';
  }

  bool get isWeakValue {
    return classification == 'WEAK VALUE';
  }

  double get aiProbabilityPercent {
    return aiProbability * 100.0;
  }

  double get marketProbabilityPercent {
    return marketProbability * 100.0;
  }

  double get edgePercent {
    return edge * 100.0;
  }

  double get expectedValuePercent {
    return expectedValue * 100.0;
  }
}

class ValueBetStore extends ChangeNotifier {
  ValueBetStore._();

  static final ValueBetStore instance = ValueBetStore._();

  final List<SavedValueBet> _items = [];

  // ============================================================
  // GETTERS
  // ============================================================

  List<SavedValueBet> get items {
    final result = List<SavedValueBet>.from(_items);

    result.sort((a, b) => b.expectedValue.compareTo(a.expectedValue));

    return List.unmodifiable(result);
  }

  List<SavedValueBet> get playable {
    return items.where((item) => item.shouldBet).toList();
  }

  List<SavedValueBet> get strongValues {
    return items.where((item) => item.isStrongValue).toList();
  }

  int get count {
    return _items.length;
  }

  int get playableCount {
    return _items.where((item) => item.shouldBet).length;
  }

  bool get isEmpty {
    return _items.isEmpty;
  }

  // ============================================================
  // ADD / UPDATE
  // ============================================================

  void addOrUpdate(SavedValueBet item) {
    final index = _items.indexWhere(
      (existing) =>
          existing.fixtureId == item.fixtureId &&
          existing.outcome == item.outcome,
    );

    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.add(item);
    }

    notifyListeners();
  }

  // ============================================================
  // REMOVE
  // ============================================================

  void remove({required int fixtureId, required String outcome}) {
    _items.removeWhere(
      (item) => item.fixtureId == fixtureId && item.outcome == outcome,
    );

    notifyListeners();
  }

  // ============================================================
  // CLEAR
  // ============================================================

  void clear() {
    if (_items.isEmpty) {
      return;
    }

    _items.clear();

    notifyListeners();
  }

  // ============================================================
  // REMOVE OLD
  // ============================================================

  void removeExpired() {
    final now = DateTime.now();

    final before = _items.length;

    _items.removeWhere((item) => item.matchDate.isBefore(now));

    if (_items.length != before) {
      notifyListeners();
    }
  }
}
