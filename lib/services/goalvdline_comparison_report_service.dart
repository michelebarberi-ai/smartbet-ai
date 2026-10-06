import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'goalvdline_comparison_stats_service.dart';

class GoalVdLineComparisonReportService {
  final GoalVdLineComparisonStatsService _statsService;

  GoalVdLineComparisonReportService({
    GoalVdLineComparisonStatsService? statsService,
  }) : _statsService = statsService ?? GoalVdLineComparisonStatsService();

  static final GoalVdLineComparisonReportService instance =
      GoalVdLineComparisonReportService();

  Future<Map<String, dynamic>> buildReport() async {
    final stats = await _statsService.calculate();

    return <String, dynamic>{
      'generatedAt': DateTime.now().toIso8601String(),

      'sample': {
        'totalRecords': stats.totalRecords,
        'comparableRecords': stats.comparableRecords,
        'incompleteRecords': stats.incompleteRecords,
        'coveragePercent': stats.coverage,
      },

      'oneXTwo': {
        'smartBetCorrect': stats.smartBetCorrect,
        'goalVdLineCorrect': stats.shadowCorrect,
        'smartBetAccuracyPercent': stats.smartBetAccuracy,
        'goalVdLineAccuracyPercent': stats.shadowAccuracy,

        'bothCorrect': stats.bothCorrect,
        'smartBetOnlyCorrect': stats.smartBetOnlyCorrect,
        'goalVdLineOnlyCorrect': stats.shadowOnlyCorrect,
        'bothWrong': stats.bothWrong,
      },

      'draws': {
        'actualDraws': stats.actualDraws,

        'smartBetPredictedDraws': stats.smartBetPredictedDraws,

        'goalVdLinePredictedDraws': stats.shadowPredictedDraws,

        'smartBetCorrectDraws': stats.smartBetCorrectDraws,

        'goalVdLineCorrectDraws': stats.shadowCorrectDraws,

        'smartBetPrecisionPercent': stats.smartBetDrawPrecision,

        'goalVdLinePrecisionPercent': stats.shadowDrawPrecision,

        'smartBetRecallPercent': stats.smartBetDrawRecall,

        'goalVdLineRecallPercent': stats.shadowDrawRecall,
      },

      'probabilities': {
        'smartBetBrier': stats.smartBetBrier,
        'goalVdLineBrier': stats.shadowBrier,
      },
    };
  }

  Future<void> printReport() async {
    try {
      final report = await buildReport();

      debugPrint('');
      debugPrint('========================================');
      debugPrint('GOALVDLINE COMPARISON REPORT');
      debugPrint('========================================');

      final sample = report['sample'] as Map<String, dynamic>;

      final oneXTwo = report['oneXTwo'] as Map<String, dynamic>;

      final draws = report['draws'] as Map<String, dynamic>;

      final probabilities = report['probabilities'] as Map<String, dynamic>;

      debugPrint(
        'Record totali: '
        '${sample['totalRecords']}',
      );

      debugPrint(
        'Confrontabili: '
        '${sample['comparableRecords']}',
      );

      debugPrint(
        'Coverage: '
        '${_format(sample['coveragePercent'])}%',
      );

      debugPrint('');
      debugPrint(
        'SmartBet accuracy: '
        '${_format(oneXTwo['smartBetAccuracyPercent'])}%',
      );

      debugPrint(
        'GoalVdLine accuracy: '
        '${_format(oneXTwo['goalVdLineAccuracyPercent'])}%',
      );

      debugPrint('');
      debugPrint(
        'SmartBet-only correct: '
        '${oneXTwo['smartBetOnlyCorrect']}',
      );

      debugPrint(
        'GoalVdLine-only correct: '
        '${oneXTwo['goalVdLineOnlyCorrect']}',
      );

      debugPrint('');
      debugPrint(
        'Pareggi reali: '
        '${draws['actualDraws']}',
      );

      debugPrint(
        'SmartBet draw precision/recall: '
        '${_format(draws['smartBetPrecisionPercent'])}% / '
        '${_format(draws['smartBetRecallPercent'])}%',
      );

      debugPrint(
        'GoalVdLine draw precision/recall: '
        '${_format(draws['goalVdLinePrecisionPercent'])}% / '
        '${_format(draws['goalVdLineRecallPercent'])}%',
      );

      debugPrint('');
      debugPrint(
        'Brier SmartBet: '
        '${_format(probabilities['smartBetBrier'], 5)}',
      );

      debugPrint(
        'Brier GoalVdLine: '
        '${_format(probabilities['goalVdLineBrier'], 5)}',
      );

      debugPrint('========================================');

      debugPrint(
        'GOALVDLINE_COMPARISON_REPORT_JSON '
        '${jsonEncode(report)}',
      );
    } catch (error, stackTrace) {
      debugPrint('GoalVdLine comparison report error: $error');

      debugPrint(stackTrace.toString());
    }
  }

  String _format(dynamic value, [int digits = 2]) {
    if (value is num) {
      return value.toDouble().toStringAsFixed(digits);
    }

    return '0.00';
  }
}
