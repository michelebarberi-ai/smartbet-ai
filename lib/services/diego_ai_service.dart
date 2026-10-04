import '../ai/goalvdline_match_engine.dart';
import '../ai/goalvdline_match_input_adapter.dart';
import '../models/goalvdline_match_engine_models.dart';
import '../models/match_dossier.dart';
import '../models/match_model.dart';
import 'match_dossier_builder.dart';
import 'odds_service.dart';
import 'value_bet_calculator.dart';

/// Risultato completo prodotto da DiegoAI.
///
/// Tutti i valori principali derivano dallo stesso Match Engine:
/// - probabilità 1X2
/// - mercati gol
/// - expected goals
/// - prediction confidence
///
/// Le quote vengono utilizzate solamente dopo la simulazione,
/// per calcolare edge ed expected value.
class DiegoAiAnalysis {
  final MatchModel match;
  final MatchDossier dossier;
  final GoalVdLineMatchEngineResult engine;
  final MatchOdds? odds;
  final ValueBetResult value;

  const DiegoAiAnalysis({
    required this.match,
    required this.dossier,
    required this.engine,
    required this.odds,
    required this.value,
  });

  int get dataConfidence => engine.dataConfidence;

  int get predictionConfidence => engine.predictionConfidence;

  double get homeProbability => engine.homeWinProbability;

  double get drawProbability => engine.drawProbability;

  double get awayProbability => engine.awayWinProbability;

  double get over15Probability => engine.over15Probability;

  double get under15Probability => engine.under15Probability;

  double get over25Probability => engine.over25Probability;

  double get under25Probability => engine.under25Probability;

  double get over35Probability => engine.over35Probability;

  double get under35Probability => engine.under35Probability;

  double get goalProbability => engine.goalProbability;

  double get noGoalProbability => engine.noGoalProbability;

  double get expectedHomeGoals => engine.expectedHomeGoals;

  double get expectedAwayGoals => engine.expectedAwayGoals;

  ValueBetOutcome? get bestValue => value.bestValue;
}

/// Orchestratore principale della nuova intelligenza GoalVdLine.
///
/// Pipeline:
///
/// Match
///   ↓
/// Match Dossier
///   ↓
/// GoalVdLine Match Engine
///   ↓
/// Prediction/Data Confidence
///   ↓
/// Quote 1X2
///   ↓
/// Value Engine
///
/// Le quote NON entrano nel Match Engine e quindi non modificano
/// artificialmente le probabilità generate dalla simulazione.
class DiegoAiService {
  final MatchDossierBuilder _dossierBuilder;
  final OddsService _oddsService;
  final ValueBetCalculator _valueBetCalculator;

  DiegoAiService({
    MatchDossierBuilder? dossierBuilder,
    OddsService? oddsService,
    ValueBetCalculator? valueBetCalculator,
  }) : _dossierBuilder = dossierBuilder ?? MatchDossierBuilder(),
       _oddsService = oddsService ?? OddsService(),
       _valueBetCalculator = valueBetCalculator ?? const ValueBetCalculator();

  Future<DiegoAiAnalysis?> analyze(
    MatchModel match, {
    int simulations = 20000,
  }) async {
    if (!match.hasTeamIds || match.fixtureId <= 0) {
      return null;
    }

    // ==========================================================
    // DOSSIER
    // ==========================================================

    final dossier = await _dossierBuilder.build(match);

    if (dossier == null) {
      return null;
    }

    // ==========================================================
    // MATCH ENGINE
    // ==========================================================

    final input = GoalVdLineMatchInputAdapter.fromDossier(
      match: match,
      dossier: dossier,
      simulations: simulations,
    );

    final engine = GoalVdLineMatchEngine.simulate(input);

    // ==========================================================
    // QUOTE
    // ==========================================================
    //
    // Le quote arrivano DOPO la simulazione.
    // Non influenzano gli expected goals o le probabilità.
    // ==========================================================

    final odds = await _oddsService.getMatchWinnerOdds(
      fixtureId: match.fixtureId,
    );

    // ==========================================================
    // VALUE
    // ==========================================================

    final rounded1x2 = _rounded1x2(
      home: engine.homeWinProbability,
      draw: engine.drawProbability,
      away: engine.awayWinProbability,
    );

    final value = _valueBetCalculator.calculate(
      homeProbability: rounded1x2.$1,
      drawProbability: rounded1x2.$2,
      awayProbability: rounded1x2.$3,
      dataConfidence: engine.dataConfidence,
      predictionConfidence: engine.predictionConfidence,
      odds: odds,
    );

    return DiegoAiAnalysis(
      match: match,
      dossier: dossier,
      engine: engine,
      odds: odds,
      value: value,
    );
  }

  /// Converte le probabilità interne 0-1 in percentuali intere
  /// garantendo sempre una somma esatta pari a 100.
  static (int, int, int) _rounded1x2({
    required double home,
    required double draw,
    required double away,
  }) {
    final raw = [
      home.clamp(0.0, 1.0).toDouble(),
      draw.clamp(0.0, 1.0).toDouble(),
      away.clamp(0.0, 1.0).toDouble(),
    ];

    final total = raw.fold<double>(0.0, (sum, value) => sum + value);

    if (total <= 0) {
      return (34, 33, 33);
    }

    final normalized = raw.map((value) => (value / total) * 100.0).toList();

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
      rounded[order[index % order.length]]++;
      missing--;
      index++;
    }

    return (rounded[0], rounded[1], rounded[2]);
  }

  void dispose() {
    _dossierBuilder.dispose();
    _oddsService.dispose();
  }
}
