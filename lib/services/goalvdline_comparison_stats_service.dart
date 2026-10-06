import 'goalvdline_comparison_store.dart';

class GoalVdLineComparisonStats {
  final int totalRecords;
  final int comparableRecords;

  final int smartBetCorrect;
  final int shadowCorrect;

  final int bothCorrect;
  final int smartBetOnlyCorrect;
  final int shadowOnlyCorrect;
  final int bothWrong;

  final int actualDraws;

  final int smartBetPredictedDraws;
  final int shadowPredictedDraws;

  final int smartBetCorrectDraws;
  final int shadowCorrectDraws;

  final double smartBetBrier;
  final double shadowBrier;

  const GoalVdLineComparisonStats({
    required this.totalRecords,
    required this.comparableRecords,
    required this.smartBetCorrect,
    required this.shadowCorrect,
    required this.bothCorrect,
    required this.smartBetOnlyCorrect,
    required this.shadowOnlyCorrect,
    required this.bothWrong,
    required this.actualDraws,
    required this.smartBetPredictedDraws,
    required this.shadowPredictedDraws,
    required this.smartBetCorrectDraws,
    required this.shadowCorrectDraws,
    required this.smartBetBrier,
    required this.shadowBrier,
  });

  int get incompleteRecords => totalRecords - comparableRecords;

  double get coverage => _percentage(comparableRecords, totalRecords);

  double get smartBetAccuracy =>
      _percentage(smartBetCorrect, comparableRecords);

  double get shadowAccuracy => _percentage(shadowCorrect, comparableRecords);

  double get smartBetDrawPrecision =>
      _percentage(smartBetCorrectDraws, smartBetPredictedDraws);

  double get shadowDrawPrecision =>
      _percentage(shadowCorrectDraws, shadowPredictedDraws);

  double get smartBetDrawRecall =>
      _percentage(smartBetCorrectDraws, actualDraws);

  double get shadowDrawRecall => _percentage(shadowCorrectDraws, actualDraws);

  static double _percentage(int numerator, int denominator) {
    if (denominator <= 0) {
      return 0.0;
    }

    return numerator / denominator * 100.0;
  }
}

class GoalVdLineComparisonStatsService {
  final GoalVdLineComparisonStore _store;

  GoalVdLineComparisonStatsService({GoalVdLineComparisonStore? store})
    : _store = store ?? GoalVdLineComparisonStore.instance;

  // ============================================================
  // CALCOLO DALLO STORE
  // ============================================================

  Future<GoalVdLineComparisonStats> calculate() async {
    final records = await _store.readAll();

    return calculateFromRecords(records);
  }

  // ============================================================
  // CALCOLO PURO
  // ============================================================

  GoalVdLineComparisonStats calculateFromRecords(
    List<GoalVdLineComparisonRecord> records,
  ) {
    var comparableRecords = 0;

    var smartBetCorrect = 0;
    var shadowCorrect = 0;

    var bothCorrect = 0;
    var smartBetOnlyCorrect = 0;
    var shadowOnlyCorrect = 0;
    var bothWrong = 0;

    var actualDraws = 0;

    var smartBetPredictedDraws = 0;
    var shadowPredictedDraws = 0;

    var smartBetCorrectDraws = 0;
    var shadowCorrectDraws = 0;

    var smartBetBrierTotal = 0.0;
    var shadowBrierTotal = 0.0;

    for (final record in records) {
      if (!record.hasSmartBet || !record.hasShadow || !record.hasActualResult) {
        continue;
      }

      final actual = record.actualResult?['outcome']?.toString().toUpperCase();

      if (actual == null || (actual != '1' && actual != 'X' && actual != '2')) {
        continue;
      }

      final smartBet = _prediction(record.smartBet!);

      final shadow = _prediction(record.shadow!);

      if (smartBet == null || shadow == null) {
        continue;
      }

      comparableRecords++;

      final smartCorrect = smartBet.outcome == actual;

      final shadowIsCorrect = shadow.outcome == actual;

      if (smartCorrect) {
        smartBetCorrect++;
      }

      if (shadowIsCorrect) {
        shadowCorrect++;
      }

      if (smartCorrect && shadowIsCorrect) {
        bothCorrect++;
      } else if (smartCorrect) {
        smartBetOnlyCorrect++;
      } else if (shadowIsCorrect) {
        shadowOnlyCorrect++;
      } else {
        bothWrong++;
      }

      if (actual == 'X') {
        actualDraws++;
      }

      if (smartBet.outcome == 'X') {
        smartBetPredictedDraws++;

        if (actual == 'X') {
          smartBetCorrectDraws++;
        }
      }

      if (shadow.outcome == 'X') {
        shadowPredictedDraws++;

        if (actual == 'X') {
          shadowCorrectDraws++;
        }
      }

      smartBetBrierTotal += _brier(smartBet, actual);

      shadowBrierTotal += _brier(shadow, actual);
    }

    final smartBetBrier = comparableRecords > 0
        ? smartBetBrierTotal / comparableRecords
        : 0.0;

    final shadowBrier = comparableRecords > 0
        ? shadowBrierTotal / comparableRecords
        : 0.0;

    return GoalVdLineComparisonStats(
      totalRecords: records.length,
      comparableRecords: comparableRecords,
      smartBetCorrect: smartBetCorrect,
      shadowCorrect: shadowCorrect,
      bothCorrect: bothCorrect,
      smartBetOnlyCorrect: smartBetOnlyCorrect,
      shadowOnlyCorrect: shadowOnlyCorrect,
      bothWrong: bothWrong,
      actualDraws: actualDraws,
      smartBetPredictedDraws: smartBetPredictedDraws,
      shadowPredictedDraws: shadowPredictedDraws,
      smartBetCorrectDraws: smartBetCorrectDraws,
      shadowCorrectDraws: shadowCorrectDraws,
      smartBetBrier: smartBetBrier,
      shadowBrier: shadowBrier,
    );
  }

  // ============================================================
  // PREDIZIONE 1X2
  // ============================================================

  _ComparisonPrediction? _prediction(Map<String, dynamic> data) {
    var home = _toDouble(data['homeProbability']);

    var draw = _toDouble(data['drawProbability']);

    var away = _toDouble(data['awayProbability']);

    if (home == null || draw == null || away == null) {
      return null;
    }

    // Accetta sia probabilità 0..1 sia percentuali 0..100.
    final maxValue = [home, draw, away].reduce((a, b) => a > b ? a : b);

    final sum = home + draw + away;

    if (maxValue <= 1.000001 && sum <= 1.500001) {
      home *= 100.0;
      draw *= 100.0;
      away *= 100.0;
    }

    home = home.clamp(0.0, 100.0);
    draw = draw.clamp(0.0, 100.0);
    away = away.clamp(0.0, 100.0);

    // Stessa regola deterministica usata dallo Shadow:
    // in caso di parità che coinvolge X, preferiamo X.
    final outcome = draw >= home && draw >= away
        ? 'X'
        : home >= away
        ? '1'
        : '2';

    return _ComparisonPrediction(
      outcome: outcome,
      home: home / 100.0,
      draw: draw / 100.0,
      away: away / 100.0,
    );
  }

  // ============================================================
  // BRIER SCORE MULTICLASS
  // ============================================================
  //
  // Più basso = migliore.
  // 0 = probabilità perfette.
  // ============================================================

  double _brier(_ComparisonPrediction prediction, String actual) {
    final actualHome = actual == '1' ? 1.0 : 0.0;

    final actualDraw = actual == 'X' ? 1.0 : 0.0;

    final actualAway = actual == '2' ? 1.0 : 0.0;

    final homeError = prediction.home - actualHome;

    final drawError = prediction.draw - actualDraw;

    final awayError = prediction.away - actualAway;

    return ((homeError * homeError) +
            (drawError * drawError) +
            (awayError * awayError)) /
        3.0;
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }
}

class _ComparisonPrediction {
  final String outcome;

  final double home;
  final double draw;
  final double away;

  const _ComparisonPrediction({
    required this.outcome,
    required this.home,
    required this.draw,
    required this.away,
  });
}
