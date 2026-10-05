import '../models/analysis_result.dart';
import 'diego_ai_service.dart';

/// Adapter temporaneo tra il nuovo motore DiegoAI
/// e le schermate legacy che utilizzano ancora AnalysisResult.
///
/// Permette di introdurre DiegoAI nell'app senza dover
/// riscrivere contemporaneamente tutte le schermate.
class DiegoAiAnalysisResultAdapter {
  const DiegoAiAnalysisResultAdapter._();

  static AnalysisResult convert(DiegoAiAnalysis analysis) {
    final probabilities = _rounded1x2(
      analysis.homeProbability,
      analysis.drawProbability,
      analysis.awayProbability,
    );

    final prediction = _mainPrediction(
      home: analysis.homeProbability,
      draw: analysis.drawProbability,
      away: analysis.awayProbability,
    );

    final bestValue = analysis.bestMultiMarketValue;

    final hasQualifiedValue = bestValue != null;

    final valueText = bestValue == null
        ? 'Nessun mercato qualificato come value.'
        : '${bestValue.classification}: '
              '${bestValue.market} @ ${bestValue.odd.toStringAsFixed(2)} '
              '• EV ${(bestValue.expectedValue * 100).toStringAsFixed(1)}%';

    final stakeRecommendation = bestValue == null
        ? 'DiegoAI non rileva una quota sufficientemente interessante.'
        : 'DiegoAI rileva ${bestValue.classification.toLowerCase()} '
              'su ${bestValue.market} @ '
              '${bestValue.odd.toStringAsFixed(2)}.';

    return AnalysisResult(
      // Per la compatibilità con la UI attuale utilizziamo
      // la Prediction Confidence come Smart Score.
      // Successivamente la UI verrà rinominata in DiegoAI Confidence.
      smartScore: analysis.predictionConfidence,

      homeProbability: probabilities.$1,
      drawProbability: probabilities.$2,
      awayProbability: probabilities.$3,

      over15Probability: _percent(analysis.over15Probability),
      under15Probability: _percent(analysis.under15Probability),

      over25Probability: _percent(analysis.over25Probability),
      under25Probability: _percent(analysis.under25Probability),

      goalProbability: _percent(analysis.goalProbability),
      noGoalProbability: _percent(analysis.noGoalProbability),

      expectedHomeGoals: analysis.expectedHomeGoals,
      expectedAwayGoals: analysis.expectedAwayGoals,

      prediction: prediction,

      valueBet: valueText,

      risk: _risk(analysis.predictionConfidence),

      shouldBet: hasQualifiedValue,

      // DiegoAI non assegna ancora uno stake definitivo.
      // Non inventiamo quindi una percentuale.
      recommendedStakePercent: 0.0,
      recommendedStakeUnits: 0.0,

      stakeOutcome: bestValue?.market ?? '',
      stakeOdd: bestValue?.odd ?? 0.0,
      stakeBookmaker: bestValue?.bookmaker ?? '',

      stakeRecommendation: stakeRecommendation,

      recommendedStakeAmount: 0.0,

      explanation: _explanation(analysis),
    );
  }

  static int _percent(double value) {
    return (value.clamp(0.0, 1.0) * 100).round();
  }

  static String _mainPrediction({
    required double home,
    required double draw,
    required double away,
  }) {
    if (home >= draw && home >= away) {
      return '1';
    }

    if (draw >= home && draw >= away) {
      return 'X';
    }

    return '2';
  }

  static String _risk(int confidence) {
    if (confidence >= 65) {
      return 'BASSO';
    }

    if (confidence >= 50) {
      return 'MEDIO';
    }

    return 'ALTO';
  }

  static String _explanation(DiegoAiAnalysis analysis) {
    final best = analysis.bestMultiMarketValue;

    final buffer = StringBuffer();

    buffer.writeln('DIEGOAI');
    buffer.writeln('Data Confidence: ${analysis.dataConfidence}/100');
    buffer.writeln(
      'Prediction Confidence: '
      '${analysis.predictionConfidence}/100',
    );
    buffer.writeln(
      'Expected Goals: '
      '${analysis.expectedHomeGoals.toStringAsFixed(2)} - '
      '${analysis.expectedAwayGoals.toStringAsFixed(2)}',
    );

    if (best == null) {
      buffer.writeln(
        'Value: nessun mercato supera contemporaneamente '
        'i filtri di confidence, edge ed expected value.',
      );
    } else {
      buffer.writeln(
        'Value: ${best.market} '
        '@ ${best.odd.toStringAsFixed(2)} '
        '(${best.classification}), '
        'Market Confidence ${best.marketConfidence}/100, '
        'EV ${(best.expectedValue * 100).toStringAsFixed(1)}%.',
      );
    }

    return buffer.toString().trim();
  }

  static (int, int, int) _rounded1x2(double home, double draw, double away) {
    final raw = [
      home.clamp(0.0, 1.0).toDouble(),
      draw.clamp(0.0, 1.0).toDouble(),
      away.clamp(0.0, 1.0).toDouble(),
    ];

    final total = raw.reduce((a, b) => a + b);

    if (total <= 0) {
      return (34, 33, 33);
    }

    final normalized = raw.map((value) => value / total * 100.0).toList();

    final rounded = normalized.map((value) => value.floor()).toList();

    var missing = 100 - rounded.reduce((a, b) => a + b);

    final order = [0, 1, 2]
      ..sort((a, b) {
        final remainderA = normalized[a] - rounded[a];

        final remainderB = normalized[b] - rounded[b];

        return remainderB.compareTo(remainderA);
      });

    var index = 0;

    while (missing > 0) {
      rounded[order[index % 3]]++;
      missing--;
      index++;
    }

    return (rounded[0], rounded[1], rounded[2]);
  }
}
