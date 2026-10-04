import '../ai/goalvdline_match_engine.dart';
import '../ai/goalvdline_match_input_adapter.dart';
import '../models/goalvdline_match_engine_models.dart';
import '../models/match_dossier.dart';
import '../models/match_model.dart';
import 'diego_ai_market_probability_service.dart';
import 'diego_ai_multi_market_value_service.dart';
import 'match_dossier_builder.dart';
import 'odds_service.dart';
import 'value_bet_calculator.dart';

/// Risultato completo prodotto da DiegoAI.
///
/// Tutti i valori principali derivano dallo stesso Match Engine:
/// - probabilità 1X2
/// - doppie chance
/// - mercati gol
/// - expected goals
/// - prediction confidence
/// - market confidence
/// - value multi-mercato
///
/// Le quote vengono utilizzate solamente dopo la simulazione,
/// per calcolare edge ed expected value.
class DiegoAiAnalysis {
  final MatchModel match;
  final MatchDossier dossier;

  final GoalVdLineMatchEngineResult engine;

  /// Catalogo completo delle probabilità DiegoAI.
  final List<DiegoAiMarketProbability> markets;

  /// Quote 1X2 mantenute anche per compatibilità
  /// con il ValueBetCalculator esistente.
  final MatchOdds? odds;

  /// Value Engine storico limitato all'1X2.
  final ValueBetResult value;

  /// Value Engine DiegoAI multi-mercato.
  final DiegoAiMultiMarketValueResult multiMarketValue;

  const DiegoAiAnalysis({
    required this.match,
    required this.dossier,
    required this.engine,
    required this.markets,
    required this.odds,
    required this.value,
    required this.multiMarketValue,
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

  /// Miglior value del vecchio calcolatore 1X2.
  ValueBetOutcome? get bestValue => value.bestValue;

  /// Miglior value rilevato da DiegoAI tra tutti i mercati.
  DiegoAiMarketValue? get bestMultiMarketValue => multiMarketValue.bestValue;
}

/// Orchestratore principale della nuova intelligenza DiegoAI.
///
/// Pipeline:
///
/// Match
///   ↓
/// Match Dossier
///   ↓
/// GoalVdLine Match Engine
///   ↓
/// Probabilità + Confidence
///   ↓
/// Quote multi-mercato
///   ↓
/// Value Engine
///
/// Le quote NON entrano nel Match Engine e quindi non modificano
/// artificialmente le probabilità generate dalla simulazione.
class DiegoAiService {
  final MatchDossierBuilder _dossierBuilder;
  final OddsService _oddsService;

  final ValueBetCalculator _valueBetCalculator;

  final DiegoAiMarketProbabilityService _marketProbabilityService;

  final DiegoAiMultiMarketValueService _multiMarketValueService;

  DiegoAiService({
    MatchDossierBuilder? dossierBuilder,
    OddsService? oddsService,
    ValueBetCalculator? valueBetCalculator,
    DiegoAiMarketProbabilityService? marketProbabilityService,
    DiegoAiMultiMarketValueService? multiMarketValueService,
  }) : _dossierBuilder = dossierBuilder ?? MatchDossierBuilder(),
       _oddsService = oddsService ?? OddsService(),
       _valueBetCalculator = valueBetCalculator ?? const ValueBetCalculator(),
       _marketProbabilityService =
           marketProbabilityService ?? const DiegoAiMarketProbabilityService(),
       _multiMarketValueService =
           multiMarketValueService ?? const DiegoAiMultiMarketValueService();

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
    // QUOTE MULTI-MERCATO
    // ==========================================================
    //
    // Una sola richiesta quote alimenta:
    // - Value 1X2
    // - Value multi-mercato
    //
    // Le quote arrivano DOPO la simulazione.
    // ==========================================================

    final fixtureOdds = await _oddsService.getFixtureMarketOdds(
      fixtureId: match.fixtureId,
    );

    final odds = fixtureOdds?.matchWinner;

    // ==========================================================
    // VALUE 1X2
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

    // ==========================================================
    // PROBABILITÀ MULTI-MERCATO
    // ==========================================================

    final markets = _marketProbabilityService.build(engine);

    // ==========================================================
    // VALUE MULTI-MERCATO
    // ==========================================================

    final multiMarketValue = _multiMarketValueService.calculate(
      engine: engine,
      odds: fixtureOdds,
      dataConfidence: engine.dataConfidence,
      predictionConfidence: engine.predictionConfidence,
    );

    return DiegoAiAnalysis(
      match: match,
      dossier: dossier,
      engine: engine,
      markets: markets,
      odds: odds,
      value: value,
      multiMarketValue: multiMarketValue,
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
