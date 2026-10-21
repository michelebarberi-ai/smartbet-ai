import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ai/goalvdline_match_engine.dart';
import '../ai/goalvdline_match_input_adapter.dart';
import '../models/goalvdline_match_engine_models.dart';
import '../models/match_dossier.dart';
import '../models/match_model.dart';
import 'diego_ai_competition_context_service.dart';
import 'diego_ai_market_probability_service.dart';
import 'european_league_strength_service.dart';
import 'european_league_strength_snapshot_store.dart';
import 'goalvdline_comparison_store.dart';
import 'diego_ai_multi_market_value_service.dart';
import 'match_dossier_builder.dart';
import 'odds_service.dart';
import 'team_league_cache_store.dart';
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

  final DiegoAiCompetitionContextService _competitionContextService;

  /// D2B.2 League Strength.
  ///
  /// Per ora esclusivamente diagnostico/shadow:
  /// non modifica probabilità, xG o selezioni.
  final EuropeanLeagueStrengthService _leagueStrengthService;

  DiegoAiService({
    MatchDossierBuilder? dossierBuilder,
    OddsService? oddsService,
    ValueBetCalculator? valueBetCalculator,
    DiegoAiMarketProbabilityService? marketProbabilityService,
    DiegoAiMultiMarketValueService? multiMarketValueService,
    DiegoAiCompetitionContextService? competitionContextService,
    EuropeanLeagueStrengthService? leagueStrengthService,
  }) : _dossierBuilder = dossierBuilder ?? MatchDossierBuilder(),
       _oddsService = oddsService ?? OddsService(),
       _valueBetCalculator = valueBetCalculator ?? const ValueBetCalculator(),
       _marketProbabilityService =
           marketProbabilityService ?? const DiegoAiMarketProbabilityService(),
       _multiMarketValueService =
           multiMarketValueService ?? const DiegoAiMultiMarketValueService(),
       _competitionContextService =
           competitionContextService ?? DiegoAiCompetitionContextService(),
       _leagueStrengthService =
           leagueStrengthService ?? _buildDefaultLeagueStrengthService();

  static EuropeanLeagueStrengthService _buildDefaultLeagueStrengthService() {
    return EuropeanLeagueStrengthService(
      teamLeagueCacheStore: SharedPreferencesTeamLeagueCacheStore(),
      snapshotStore: SharedPreferencesEuropeanLeagueStrengthSnapshotStore(),
    );
  }

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
    // COMPETITION CONTEXT - D2B.1 SHADOW
    // ==========================================================
    //
    // D2B è ancora sperimentale.
    //
    // In DEBUG:
    // - costruisce il contesto europeo;
    // - calcola l'adjustment sperimentale;
    // - produce log e simulazione shadow.
    //
    // In RELEASE:
    // - nessuna chiamata aggiuntiva;
    // - nessun effetto sugli expected goals;
    // - Diego usa esclusivamente il modello sportivo stabile.
    //
    // Le quote NON vengono utilizzate.
    // ==========================================================

    var shadowCompetitionAdjustment = DiegoCompetitionAdjustment.neutral;

    if (kDebugMode && match.isEuropeanCup) {
      try {
        final competitionContext = await _competitionContextService.build(
          match: match,
          dossier: dossier,
        );

        if (competitionContext != null) {
          shadowCompetitionAdjustment = competitionContext
              .calculateAdjustment();

          competitionContext.logShadow();
          competitionContext.logAdjustment(shadowCompetitionAdjustment);
        }
      } catch (e) {
        shadowCompetitionAdjustment = DiegoCompetitionAdjustment.neutral;

        print('');
        print('DIEGO COMPETITION CONTEXT D2B SHADOW ERROR: $e');
      }
    }

    // ==========================================================
    // MATCH ENGINE
    // ==========================================================

    // Engine ATTIVO:
    // nessun adjustment D2B sperimentale.
    final input = GoalVdLineMatchInputAdapter.fromDossier(
      match: match,
      dossier: dossier,
      simulations: simulations,
    );

    final engine = GoalVdLineMatchEngine.simulate(input);

    // Engine SHADOW:
    // esiste solo in debug e non influenza Diego reale.
    if (kDebugMode && match.isEuropeanCup) {
      try {
        await _logLeagueStrengthShadow(
          match: match,
          dossier: dossier,
          activeHomeXg: engine.expectedHomeGoals,
          activeAwayXg: engine.expectedAwayGoals,
        );
      } catch (e) {
        print('');
        print('DIEGO D2B.2 PROSPECTIVE SHADOW ERROR: $e');
      }

      final shadowInput = GoalVdLineMatchInputAdapter.fromDossier(
        match: match,
        dossier: dossier,
        simulations: simulations,
        homeContextAdjustment: shadowCompetitionAdjustment.homeAdjustment,
        awayContextAdjustment: shadowCompetitionAdjustment.awayAdjustment,
      );

      final shadowEngine = GoalVdLineMatchEngine.simulate(shadowInput);

      print(
        'DIEGO_D2B_SHADOW_ENGINE_JSON '
        '{'
        '"fixtureId":${match.fixtureId},'
        '"homeTeam":"${match.homeTeam}",'
        '"awayTeam":"${match.awayTeam}",'
        '"shadowHomeContext":'
        '${shadowCompetitionAdjustment.homeAdjustment},'
        '"shadowAwayContext":'
        '${shadowCompetitionAdjustment.awayAdjustment},'
        '"activeExpectedHomeGoals":${engine.expectedHomeGoals},'
        '"activeExpectedAwayGoals":${engine.expectedAwayGoals},'
        '"activeHomeProbability":${engine.homeWinProbability},'
        '"activeDrawProbability":${engine.drawProbability},'
        '"activeAwayProbability":${engine.awayWinProbability},'
        '"shadowExpectedHomeGoals":'
        '${shadowEngine.expectedHomeGoals},'
        '"shadowExpectedAwayGoals":'
        '${shadowEngine.expectedAwayGoals},'
        '"shadowHomeProbability":'
        '${shadowEngine.homeWinProbability},'
        '"shadowDrawProbability":'
        '${shadowEngine.drawProbability},'
        '"shadowAwayProbability":'
        '${shadowEngine.awayWinProbability}'
        '}',
      );
    }

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

  Future<void> _logLeagueStrengthShadow({
    required MatchModel match,
    required MatchDossier dossier,
    required double activeHomeXg,
    required double activeAwayXg,
  }) async {
    final referenceDate = DateTime.tryParse(match.date);

    if (referenceDate == null) {
      return;
    }

    final season = referenceDate.month <= 6
        ? referenceDate.year - 1
        : referenceDate.year;

    final homeLeagueId = dossier.homeCurrentLeagueId;

    final awayLeagueId = dossier.awayCurrentLeagueId;

    if (homeLeagueId <= 0 || awayLeagueId <= 0) {
      print(
        'DIEGO_D2B2_LEAGUE_STRENGTH_SHADOW '
        'N/D | campionato domestico mancante',
      );
      return;
    }

    final snapshot = await _leagueStrengthService.build(
      currentSeason: season,
      referenceDate: referenceDate,
    );

    if (snapshot == null) {
      print(
        'DIEGO_D2B2_LEAGUE_STRENGTH_SHADOW '
        'N/D | snapshot non disponibile',
      );
      return;
    }

    final homeLeague = snapshot.forLeague(homeLeagueId);

    final awayLeague = snapshot.forLeague(awayLeagueId);

    if (homeLeague == null || awayLeague == null) {
      print(
        'DIEGO_D2B2_LEAGUE_STRENGTH_SHADOW '
        'N/D | lega non presente nel modello',
      );
      return;
    }

    if (homeLeagueId == awayLeagueId) {
      print(
        'DIEGO_D2B2_LEAGUE_STRENGTH_SHADOW '
        '{'
        '"fixtureId":${match.fixtureId},'
        '"season":$season,'
        '"homeLeagueId":$homeLeagueId,'
        '"awayLeagueId":$awayLeagueId,'
        '"sameLeague":true,'
        '"adjustmentApplied":false'
        '}',
      );
      return;
    }

    final comparison = snapshot.compareLeagues(homeLeagueId, awayLeagueId);

    if (comparison == null) {
      print(
        'DIEGO_D2B2_LEAGUE_STRENGTH_SHADOW '
        'N/D | confronto non disponibile',
      );
      return;
    }

    // Il timestamp viene preso DOPO aver terminato la costruzione
    // del League Strength. In questo modo, se il calcolo termina
    // dopo il kickoff, il record NON può risultare prospettico.
    final capturedAt = DateTime.now();

    final statusShort = match.statusShort.trim().toUpperCase();

    final statusIsNotStarted = statusShort == 'NS';

    final capturedBeforeKickoff = capturedAt.isBefore(referenceDate);

    final prospectiveEligible = statusIsNotStarted && capturedBeforeKickoff;

    final leagueStrengthPayload = <String, dynamic>{
      'modelVersion':
          'd2b2_ls_v1_prev1_qual05_main1_lambda3_gate1_c90v1_mainstagev1',
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'kickoff': referenceDate.toUtc().toIso8601String(),
      'statusShort': statusShort,
      'statusIsNotStarted': statusIsNotStarted,
      'capturedBeforeKickoff': capturedBeforeKickoff,
      'prospectiveEligible': prospectiveEligible,
      'fixtureId': match.fixtureId,
      'season': season,
      'homeTeam': match.homeTeam,
      'awayTeam': match.awayTeam,
      'homeLeagueId': homeLeagueId,
      'homeLeague': homeLeague.leagueName,
      'homeRating': homeLeague.rating,
      'homeSE': homeLeague.standardError,
      'awayLeagueId': awayLeagueId,
      'awayLeague': awayLeague.leagueName,
      'awayRating': awayLeague.rating,
      'awaySE': awayLeague.standardError,
      'ratingDifference': comparison.ratingDifference,
      'differenceSE': comparison.standardError,
      'snr': comparison.signalToNoise,
      'passesEvidenceGate': comparison.passesEvidenceGate,
      'activeHomeXg': activeHomeXg,
      'activeAwayXg': activeAwayXg,
      'adjustmentApplied': false,
      'oddsUsed': false,
      'captureMode': 'debug_shadow',
    };

    GoalVdLineComparisonStore.instance.registerLeagueStrength(
      match: match,
      leagueStrength: leagueStrengthPayload,
    );

    print(
      'DIEGO_D2B2_LEAGUE_STRENGTH_SHADOW '
      '${jsonEncode(leagueStrengthPayload)}',
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
    _leagueStrengthService.dispose();
  }
}
