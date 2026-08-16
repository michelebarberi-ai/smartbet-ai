import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';

class SavedPrediction {
  final int fixtureId;

  final String matchLabel;

  final String league;

  final DateTime matchDate;

  final int smartScore;

  final int homeProbability;

  final int drawProbability;

  final int awayProbability;

  final String prediction;

  final String valueBet;

  final String risk;

  final bool shouldBet;

  final double recommendedStakePercent;

  final String stakeOutcome;

  final double stakeOdd;

  final String stakeBookmaker;

  final String stakeRecommendation;

  final DateTime createdAt;

  const SavedPrediction({
    required this.fixtureId,
    required this.matchLabel,
    required this.league,
    required this.matchDate,
    required this.smartScore,
    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,
    required this.prediction,
    required this.valueBet,
    required this.risk,
    required this.shouldBet,
    required this.recommendedStakePercent,
    required this.stakeOutcome,
    required this.stakeOdd,
    required this.stakeBookmaker,
    required this.stakeRecommendation,
    required this.createdAt,
  });

  int get bestProbability {
    return [
      homeProbability,
      drawProbability,
      awayProbability,
    ].reduce((a, b) => a > b ? a : b);
  }

  String get bestOutcome {
    if (homeProbability >= drawProbability &&
        homeProbability >= awayProbability) {
      return '1';
    }

    if (drawProbability >= homeProbability &&
        drawProbability >= awayProbability) {
      return 'X';
    }

    return '2';
  }
}

class PredictionStore extends ChangeNotifier {
  PredictionStore._();

  static final PredictionStore instance = PredictionStore._();

  final List<SavedPrediction> _items = [];

  // ============================================================
  // GETTERS
  // ============================================================

  List<SavedPrediction> get items {
    final result = List<SavedPrediction>.from(_items);

    result.sort((a, b) {
      final scoreComparison = b.smartScore.compareTo(a.smartScore);

      if (scoreComparison != 0) {
        return scoreComparison;
      }

      return b.bestProbability.compareTo(a.bestProbability);
    });

    return List.unmodifiable(result);
  }

  List<SavedPrediction> get playable {
    return items.where((item) => item.shouldBet).toList();
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

  void addOrUpdate(SavedPrediction item) {
    final index = _items.indexWhere(
      (existing) => existing.fixtureId == item.fixtureId,
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

  void remove(int fixtureId) {
    final before = _items.length;

    _items.removeWhere((item) => item.fixtureId == fixtureId);

    if (_items.length != before) {
      notifyListeners();
    }
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
  // REMOVE EXPIRED
  // ============================================================

  void removeExpired() {
    final now = DateTime.now();

    final before = _items.length;

    _items.removeWhere((item) => item.matchDate.isBefore(now));

    if (_items.length != before) {
      notifyListeners();
    }
  }

  // ============================================================
  // CREA DA ANALYSIS RESULT
  // ============================================================

  void register({required MatchModel match, required AnalysisResult result}) {
    if (result.smartScore <= 0) {
      return;
    }

    DateTime matchDate;

    try {
      matchDate = DateTime.parse(match.date).toLocal();
    } catch (_) {
      matchDate = DateTime.now();
    }

    addOrUpdate(
      SavedPrediction(
        fixtureId: match.fixtureId,

        matchLabel:
            '${match.homeTeam} - '
            '${match.awayTeam}',

        league: match.league,

        matchDate: matchDate,

        smartScore: result.smartScore,

        homeProbability: result.homeProbability,

        drawProbability: result.drawProbability,

        awayProbability: result.awayProbability,

        prediction: result.prediction,

        valueBet: result.valueBet,

        risk: result.risk,

        shouldBet: result.shouldBet,

        recommendedStakePercent: result.recommendedStakePercent,

        stakeOutcome: result.stakeOutcome,

        stakeOdd: result.stakeOdd,

        stakeBookmaker: result.stakeBookmaker,

        stakeRecommendation: result.stakeRecommendation,

        createdAt: DateTime.now(),
      ),
    );
  }
}
