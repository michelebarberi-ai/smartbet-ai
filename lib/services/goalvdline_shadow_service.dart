import 'dart:convert';

import '../ai/goalvdline_match_engine.dart';
import '../ai/goalvdline_match_input_adapter.dart';
import '../models/match_dossier.dart';
import '../models/match_model.dart';

import 'goalvdline_comparison_store.dart';

class GoalVdLineShadowSnapshot {
  final int fixtureId;

  final String homeTeam;
  final String awayTeam;

  final String prediction;

  final double homeProbability;
  final double drawProbability;
  final double awayProbability;

  final double over15Probability;
  final double over25Probability;
  final double over35Probability;

  final double goalProbability;

  final double expectedHomeGoals;
  final double expectedAwayGoals;

  final int dataConfidence;
  final int predictionConfidence;

  final int simulations;

  final DateTime capturedAt;

  const GoalVdLineShadowSnapshot({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.prediction,
    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,
    required this.over15Probability,
    required this.over25Probability,
    required this.over35Probability,
    required this.goalProbability,
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
    required this.dataConfidence,
    required this.predictionConfidence,
    required this.simulations,
    required this.capturedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'fixtureId': fixtureId,
      'homeTeam': homeTeam,
      'awayTeam': awayTeam,
      'prediction': prediction,
      'homeProbability': homeProbability,
      'drawProbability': drawProbability,
      'awayProbability': awayProbability,
      'over15Probability': over15Probability,
      'under15Probability': 100.0 - over15Probability,
      'over25Probability': over25Probability,
      'under25Probability': 100.0 - over25Probability,
      'over35Probability': over35Probability,
      'under35Probability': 100.0 - over35Probability,
      'goalProbability': goalProbability,
      'noGoalProbability': 100.0 - goalProbability,
      'expectedHomeGoals': expectedHomeGoals,
      'expectedAwayGoals': expectedAwayGoals,
      'expectedTotalGoals': expectedHomeGoals + expectedAwayGoals,
      'dataConfidence': dataConfidence,
      'predictionConfidence': predictionConfidence,
      'simulations': simulations,
      'capturedAt': capturedAt.toIso8601String(),
    };
  }
}

class GoalVdLineShadowService {
  const GoalVdLineShadowService._();

  // ============================================================
  // SHADOW MODE
  // ============================================================
  //
  // Non deve MAI modificare il risultato SmartBet.
  // Non deve MAI impedire all'analisi principale di continuare.
  //
  // V3 Draw non viene applicata qui:
  // resta congelata nella Validation 2 prospettica.
  // ============================================================

  static const bool enabled = true;

  static const int simulations = 20000;

  static final Map<int, GoalVdLineShadowSnapshot> _snapshots =
      <int, GoalVdLineShadowSnapshot>{};

  static Map<int, GoalVdLineShadowSnapshot> get snapshots =>
      Map<int, GoalVdLineShadowSnapshot>.unmodifiable(_snapshots);

  static GoalVdLineShadowSnapshot? forFixture(int fixtureId) {
    return _snapshots[fixtureId];
  }

  static void clear() {
    _snapshots.clear();
  }

  static void capture({
    required MatchModel match,
    required MatchDossier? dossier,
  }) {
    if (!enabled) {
      return;
    }

    if (dossier == null) {
      return;
    }

    if (!match.hasTeamIds || match.fixtureId <= 0) {
      return;
    }

    // Lo shadow viene accodato e non viene atteso da SmartBet.
    // Qualunque errore resta confinato qui.
    Future<void>(() {
      try {
        final input = GoalVdLineMatchInputAdapter.fromDossier(
          match: match,
          dossier: dossier,
          simulations: simulations,
        );

        final engine = GoalVdLineMatchEngine.simulate(input);

        final prediction = _prediction(
          home: engine.homeWinPercent,
          draw: engine.drawPercent,
          away: engine.awayWinPercent,
        );

        final snapshot = GoalVdLineShadowSnapshot(
          fixtureId: match.fixtureId,
          homeTeam: match.homeTeam,
          awayTeam: match.awayTeam,
          prediction: prediction,
          homeProbability: engine.homeWinPercent,
          drawProbability: engine.drawPercent,
          awayProbability: engine.awayWinPercent,
          over15Probability: engine.over15Percent,
          over25Probability: engine.over25Percent,
          over35Probability: engine.over35Percent,
          goalProbability: engine.goalPercent,
          expectedHomeGoals: engine.expectedHomeGoals,
          expectedAwayGoals: engine.expectedAwayGoals,
          dataConfidence: engine.dataConfidence,
          predictionConfidence: engine.predictionConfidence,
          simulations: engine.simulations,
          capturedAt: DateTime.now(),
        );

        _snapshots[match.fixtureId] = snapshot;

        GoalVdLineComparisonStore.instance.registerShadow(
          match: match,
          shadow: snapshot.toJson(),
        );

        print('');
        print('========================================');
        print('GOALVDLINE SHADOW MODE');
        print('========================================');
        print('${match.homeTeam} - ${match.awayTeam}');
        print('Fixture: ${match.fixtureId}');
        print('Pronostico shadow: $prediction');
        print('1: ${engine.homeWinPercent.toStringAsFixed(1)}%');
        print('X: ${engine.drawPercent.toStringAsFixed(1)}%');
        print('2: ${engine.awayWinPercent.toStringAsFixed(1)}%');
        print(
          'xG: '
          '${engine.expectedHomeGoals.toStringAsFixed(2)}'
          ' - '
          '${engine.expectedAwayGoals.toStringAsFixed(2)}',
        );
        print(
          'Confidence: '
          '${engine.predictionConfidence}%',
        );
        print('========================================');

        print(
          'GOALVDLINE_SHADOW_JSON '
          '${jsonEncode(snapshot.toJson())}',
        );
      } catch (error, stackTrace) {
        // Shadow mode è best-effort.
        // SmartBet non deve mai fallire per questo motivo.
        print('');
        print('GOALVDLINE SHADOW ERROR');
        print(error);
        print(stackTrace);
      }
    });
  }

  static String _prediction({
    required double home,
    required double draw,
    required double away,
  }) {
    if (draw >= home && draw >= away) {
      return 'X';
    }

    if (home >= away) {
      return '1';
    }

    return '2';
  }
}
