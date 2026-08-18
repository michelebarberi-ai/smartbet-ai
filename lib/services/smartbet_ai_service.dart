import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../ai/smartcore.dart';
import '../ai/decision_engine.dart';

import 'match_dossier_builder.dart';
import 'odds_service.dart';
import 'stake_engine.dart';
import 'value_bet_calculator.dart';
import 'value_bet_store.dart';
import 'prediction_store.dart';

class SmartBetAiService {
  final http.Client _client;

  final MatchDossierBuilder _dossierBuilder;

  final OddsService _oddsService;

  final ValueBetCalculator _valueBetCalculator;

  final StakeEngine _stakeEngine;

  SmartBetAiService({
    http.Client? client,
    MatchDossierBuilder? dossierBuilder,
    OddsService? oddsService,
    ValueBetCalculator? valueBetCalculator,
    StakeEngine? stakeEngine,
  }) : _client = client ?? http.Client(),
       _dossierBuilder = dossierBuilder ?? MatchDossierBuilder(),
       _oddsService = oddsService ?? OddsService(),
       _valueBetCalculator = valueBetCalculator ?? const ValueBetCalculator(),
       _stakeEngine = stakeEngine ?? const StakeEngine();

  // ============================================================
  // BACKEND
  // ============================================================

  static const String backendUrl = 'https://smartbet-ai-y6gw.onrender.com';
  // ============================================================
  // ANALISI PARTITA
  // ============================================================

  Future<AnalysisResult> analyzeMatch(MatchModel match) async {
    print('');
    print('========================================');
    print('SMARTBET AI - ANALISI PARTITA');
    print('========================================');

    print(
      'Partita: '
      '${match.homeTeam} - ${match.awayTeam}',
    );

    print(
      'Fixture ID: '
      '${match.fixtureId}',
    );

    print('Data: ${match.date}');

    print(
      'Competizione: '
      '${match.league}',
    );

    print('========================================');

    // ==========================================================
    // CONTROLLO ID
    // ==========================================================

    if (!match.hasTeamIds) {
      return _errorResult('ID delle squadre non disponibili.');
    }

    // ==========================================================
    // SMARTCORE LOCALE
    // ==========================================================
    //
    // Manteniamo l'analisi avanzata del backend per:
    // 1X2, dossier, news, value bet e stake.
    //
    // SmartCore calcola invece i mercati:
    // OVER / UNDER 1.5
    // OVER / UNDER 2.5
    // GOAL / NO GOAL
    // ==========================================================

    final baseResult = await SmartCore.analyze(match);

    print('');
    print('========================================');
    print('SMARTBET - QUOTE GOL');
    print('========================================');
    print('OVER 1.5: ${baseResult.over15Probability}%');
    print('UNDER 1.5: ${baseResult.under15Probability}%');
    print('OVER 2.5: ${baseResult.over25Probability}%');
    print('UNDER 2.5: ${baseResult.under25Probability}%');
    print('GOAL: ${baseResult.goalProbability}%');
    print('NO GOAL: ${baseResult.noGoalProbability}%');
    print('========================================');

    // ==========================================================
    // DOSSIER
    // ==========================================================

    print('');
    print('========================================');
    print('SMARTBET AI - COSTRUZIONE DOSSIER');
    print('========================================');

    final dossier = await _dossierBuilder.build(match);

    if (dossier == null) {
      return _errorResult(
        'Impossibile costruire '
        'il Match Dossier.',
      );
    }

    print('');
    print('========================================');
    print('SMARTBET AI - DOSSIER PRONTO');
    print('========================================');

    print(
      'Partita: '
      '${dossier.homeTeam} - '
      '${dossier.awayTeam}',
    );

    print(
      'Data confidence: '
      '${dossier.dataConfidence}%',
    );

    print(
      'Pre-match only: '
      '${dossier.preMatchOnly}',
    );

    print(
      'Forma casa: '
      '${dossier.homeForm['count'] ?? 0}',
    );

    print(
      'Forma ospite: '
      '${dossier.awayForm['count'] ?? 0}',
    );

    print(
      'H2H: '
      '${dossier.headToHead.length}',
    );

    print(
      'Assenze: '
      '${dossier.injuries.length}',
    );

    print(
      'Formazioni: '
      '${dossier.probableLineups.length}',
    );

    print('========================================');

    // ==========================================================
    // ODDS
    // ==========================================================

    final odds = await _oddsService.getMatchWinnerOdds(
      fixtureId: match.fixtureId,
    );

    if (odds == null) {
      print('');
      print(
        'SMARTBET: quote 1X2 '
        'non disponibili.',
      );
    }

    // ==========================================================
    // BACKEND
    // ==========================================================

    try {
      final uri = Uri.parse('$backendUrl/analyze');

      final body = jsonEncode({
        'homeTeam': match.homeTeam,

        'awayTeam': match.awayTeam,

        'matchDate': match.date,

        'dossier': dossier.toJson(),

        'meta': {
          'fixtureId': match.fixtureId,

          'league': match.league,

          'leagueId': match.leagueId,

          'country': match.country,

          'leagueType': match.leagueType,

          'isEuropeanCup': match.isEuropeanCup,

          'isFriendly': match.isFriendly,

          'isNational': match.isNational,

          'aiWeight': match.aiWeight,

          'oddsAvailable': odds != null,
        },
      });

      print('');
      print('========================================');
      print('SMARTBET AI - INVIO BACKEND');
      print('========================================');

      print('URL: $uri');

      print(
        'Dossier confidence: '
        '${dossier.dataConfidence}%',
      );

      print(
        'Quote disponibili: '
        '${odds != null}',
      );

      print(
        'Payload length: '
        '${body.length}',
      );

      print('========================================');

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      print('');

      print(
        'AI STATUS CODE: '
        '${response.statusCode}',
      );

      print(
        'AI RESPONSE LENGTH: '
        '${response.body.length}',
      );

      // ========================================================
      // ERRORE BACKEND
      // ========================================================

      if (response.statusCode != 200) {
        print('');
        print('SMARTBET AI BACKEND ERROR');

        print(response.body);

        try {
          final errorDecoded = jsonDecode(response.body);

          if (errorDecoded is Map<String, dynamic>) {
            return _errorResult(
              errorDecoded['error']?.toString() ?? 'Errore backend AI.',
            );
          }
        } catch (_) {}

        return _errorResult(
          'Il backend AI ha restituito '
          'lo stato ${response.statusCode}.',
        );
      }

      // ========================================================
      // JSON
      // ========================================================

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return _errorResult(
          'Risposta backend '
          'non valida.',
        );
      }

      if (decoded['success'] != true) {
        return _errorResult(
          decoded['error']?.toString() ?? 'Errore backend AI.',
        );
      }

      final analysis = decoded['analysis'];

      if (analysis is! Map<String, dynamic>) {
        return _errorResult(
          'Analisi AI '
          'non presente.',
        );
      }

      // ========================================================
      // META
      // ========================================================

      final backendMeta = decoded['meta'];

      if (backendMeta is Map<String, dynamic>) {
        print('');
        print('BACKEND META');

        print(
          'Match status: '
          '${backendMeta['matchStatus']}',
        );

        print(
          'Pre-match protected: '
          '${backendMeta['preMatchProtected']}',
        );
      }

      return _parseAnalysisResult(
        analysis: analysis,
        match: match,
        dossierConfidence: dossier.dataConfidence,
        odds: odds,
        baseResult: baseResult,
      );
    } catch (e) {
      print('');
      print('========================================');
      print('SMARTBET AI EXCEPTION');
      print('========================================');

      print(e);

      return _errorResult(
        'Errore di connessione '
        'al backend AI: $e',
      );
    }
  }

  // ============================================================
  // PARSING
  // ============================================================

  AnalysisResult _parseAnalysisResult({
    required Map<String, dynamic> analysis,
    required MatchModel match,
    required int dossierConfidence,
    required MatchOdds? odds,
    required AnalysisResult baseResult,
  }) {
    final backendPrediction = analysis['prediction']?.toString() ?? 'N/D';

    final homeProbability = _toInt(analysis['homeProbability']);

    final drawProbability = _toInt(analysis['drawProbability']);

    final awayProbability = _toInt(analysis['awayProbability']);

    final smartDecision = DecisionEngine.decide(
      homeProbability: homeProbability,
      drawProbability: drawProbability,
      awayProbability: awayProbability,
    );

    final prediction = smartDecision.outcome;

    final predictionProbability = smartDecision.probability;

    final confidence = _toInt(analysis['confidence']);

    final risk = analysis['risk']?.toString() ?? 'N/D';

    final summary = analysis['summary']?.toString() ?? '';

    final statisticalAnalysis =
        analysis['statisticalAnalysis']?.toString() ?? '';

    final newsAnalysis = analysis['newsAnalysis']?.toString() ?? '';

    final positiveFactors = _toStringList(analysis['positiveFactors']);

    final negativeFactors = _toStringList(analysis['negativeFactors']);

    final keyAbsences = _toStringList(analysis['keyAbsences']);

    final finalVerdict = analysis['finalVerdict']?.toString() ?? '';

    // ==========================================================
    // VALUE BET
    // ==========================================================

    final valueResult = _valueBetCalculator.calculate(
      homeProbability: homeProbability,
      drawProbability: drawProbability,
      awayProbability: awayProbability,
      dataConfidence: dossierConfidence,
      odds: odds,
    );

    final valueBet = valueResult.explanation;

    // ==========================================================
    // STAKE ENGINE
    // ==========================================================

    final stake = _stakeEngine.calculate(
      valueResult: valueResult,
      aiConfidence: confidence,
      dossierConfidence: dossierConfidence,
      risk: risk,
    );

    // ==========================================================
    // VALUE BET STORE
    // ==========================================================

    final bestValue = valueResult.bestValue;

    if (bestValue != null) {
      DateTime matchDate;

      try {
        matchDate = DateTime.parse(match.date).toLocal();
      } catch (_) {
        matchDate = DateTime.now();
      }

      ValueBetStore.instance.addOrUpdate(
        SavedValueBet(
          fixtureId: match.fixtureId,

          matchLabel:
              '${match.homeTeam} - '
              '${match.awayTeam}',

          league: match.league,

          matchDate: matchDate,

          outcome: bestValue.outcome,

          odd: bestValue.bestOdd,

          bookmaker: bestValue.bookmakerName,

          aiProbability: bestValue.aiProbability,

          marketProbability: bestValue.fairMarketProbability,

          edge: bestValue.edge,

          expectedValue: bestValue.expectedValue,

          fairOdd: bestValue.smartBetFairOdd,

          classification: bestValue.classification,

          aiConfidence: confidence,

          dossierConfidence: dossierConfidence,

          shouldBet: stake.shouldBet,

          stakePercent: stake.stakePercent,

          createdAt: DateTime.now(),
        ),
      );
    }

    // ==========================================================
    // PREDICTION STORE
    // ==========================================================

    final predictionResult = AnalysisResult(
      smartScore: confidence,
      homeProbability: homeProbability,
      drawProbability: drawProbability,
      awayProbability: awayProbability,

      over15Probability: baseResult.over15Probability,
      under15Probability: baseResult.under15Probability,
      over25Probability: baseResult.over25Probability,
      under25Probability: baseResult.under25Probability,
      goalProbability: baseResult.goalProbability,
      noGoalProbability: baseResult.noGoalProbability,

      prediction: prediction,
      valueBet: valueBet,
      risk: risk,
      shouldBet: stake.shouldBet,
      recommendedStakePercent: stake.stakePercent,
      recommendedStakeUnits: stake.stakeUnits,
      stakeOutcome: stake.outcome,
      stakeOdd: stake.odd,
      stakeBookmaker: stake.bookmakerName,
      stakeRecommendation: stake.explanation,
      explanation: '',
    );

    PredictionStore.instance.register(match: match, result: predictionResult);

    // ==========================================================
    // MATCH
    // ==========================================================

    match.smartScore = confidence;

    match.homeWin = homeProbability;

    match.draw = drawProbability;

    match.awayWin = awayProbability;

    match.valueBet = valueBet;

    // ==========================================================
    // AI LOG
    // ==========================================================

    print('');
    print('========================================');
    print('SMARTBET AI - RISULTATO');
    print('========================================');

    print('Pronostico SmartBet: $prediction');
    print('Affidabilità pronostico: $predictionProbability%');
    print('Pronostico backend originale: $backendPrediction');

    print('1: $homeProbability%');

    print('X: $drawProbability%');

    print('2: $awayProbability%');

    print(
      'Confidence AI: '
      '$confidence%',
    );

    print(
      'Confidence dossier: '
      '$dossierConfidence%',
    );

    print('Risk: $risk');

    print('========================================');

    // ==========================================================
    // VALUE BET
    // ==========================================================

    print('');
    print('========================================');
    print('SMARTBET - VALUE BET');
    print('========================================');

    print(
      'Quote disponibili: '
      '${valueResult.oddsAvailable}',
    );

    if (odds != null) {
      print(
        'Bookmaker analizzati: '
        '${odds.bookmakerCount}',
      );

      print(
        'Mercato fair: '
        '${odds.referenceMarket.bookmakerName}',
      );

      print(
        'Margine fair: '
        '${(odds.bookmakerMargin * 100).toStringAsFixed(2)}%',
      );

      print('');

      _printOutcome(valueResult.home);

      _printOutcome(valueResult.draw);

      _printOutcome(valueResult.away);
    }

    print(
      'CLASSIFICAZIONE FINALE: '
      '${valueResult.label}',
    );

    print(valueResult.explanation);

    print('========================================');

    // ==========================================================
    // STAKE ENGINE
    // ==========================================================

    print('');
    print('========================================');
    print('SMARTBET - STAKE ENGINE');
    print('========================================');

    print(
      'Giocabile: '
      '${stake.shouldBet}',
    );

    if (stake.shouldBet) {
      print(
        'Esito: '
        '${stake.outcome}',
      );

      print(
        'Quota: '
        '${stake.odd.toStringAsFixed(2)}',
      );

      print(
        'Bookmaker: '
        '${stake.bookmakerName}',
      );

      print(
        'Stake bankroll: '
        '${stake.stakePercent.toStringAsFixed(2)}%',
      );

      print(
        'Stake unità: '
        '${stake.stakeUnits.toStringAsFixed(2)}',
      );

      print(
        'Kelly pieno: '
        '${(stake.fullKellyFraction * 100).toStringAsFixed(2)}%',
      );

      print(
        'Kelly corretto: '
        '${(stake.adjustedKellyFraction * 100).toStringAsFixed(2)}%',
      );
    }

    print(
      'Decisione: '
      '${stake.explanation}',
    );

    print('========================================');

    // ==========================================================
    // EXPLANATION
    // ==========================================================

    final explanation =
        '''
SMARTBET AI

PRONOSTICO SMARTBET: $prediction
AFFIDABILITÀ PRONOSTICO: $predictionProbability%

MOTIVAZIONE DECISIONE:
${smartDecision.reason}

PROBABILITÀ 1X2:
1: $homeProbability%
X: $drawProbability%
2: $awayProbability%

PRONOSTICO BACKEND ORIGINALE: $backendPrediction

CONFIDENCE AI: $confidence%

CONFIDENCE DOSSIER: $dossierConfidence%

RISCHIO:
$risk

--------------------------------------------------
SINTESI
--------------------------------------------------

$summary

--------------------------------------------------
ANALISI STATISTICA
--------------------------------------------------

$statisticalAnalysis

--------------------------------------------------
ANALISI NOTIZIE
--------------------------------------------------

$newsAnalysis

--------------------------------------------------
FATTORI POSITIVI
--------------------------------------------------

${positiveFactors.map((e) => '• $e').join('\n')}

--------------------------------------------------
FATTORI NEGATIVI
--------------------------------------------------

${negativeFactors.map((e) => '• $e').join('\n')}

--------------------------------------------------
ASSENZE
--------------------------------------------------

${keyAbsences.map((e) => '• $e').join('\n')}

--------------------------------------------------
BEST ODDS / VALUE BET
--------------------------------------------------

$valueBet

--------------------------------------------------
STAKE ENGINE
--------------------------------------------------

${stake.explanation}

--------------------------------------------------
VERDETTO FINALE AI
--------------------------------------------------

$finalVerdict
''';

    return AnalysisResult(
      smartScore: confidence,

      homeProbability: homeProbability,

      drawProbability: drawProbability,

      awayProbability: awayProbability,

      over15Probability: baseResult.over15Probability,
      under15Probability: baseResult.under15Probability,
      over25Probability: baseResult.over25Probability,

      under25Probability: baseResult.under25Probability,

      goalProbability: baseResult.goalProbability,

      noGoalProbability: baseResult.noGoalProbability,

      prediction: prediction,

      valueBet: valueBet,

      risk: risk,

      shouldBet: stake.shouldBet,

      recommendedStakePercent: stake.stakePercent,

      recommendedStakeUnits: stake.stakeUnits,

      stakeOutcome: stake.outcome,

      stakeOdd: stake.odd,

      stakeBookmaker: stake.bookmakerName,

      stakeRecommendation: stake.explanation,

      explanation: explanation,
    );
  }

  // ============================================================
  // LOG VALUE OUTCOME
  // ============================================================

  void _printOutcome(ValueBetOutcome? item) {
    if (item == null) {
      return;
    }

    print('ESITO ${item.outcome}');

    print(
      'Best Odd: '
      '${item.bestOdd.toStringAsFixed(2)} '
      '(${item.bookmakerName})',
    );

    print(
      'Quota equa SmartBet: '
      '${item.smartBetFairOdd.toStringAsFixed(2)}',
    );

    print(
      'AI: '
      '${(item.aiProbability * 100).toStringAsFixed(1)}%',
    );

    print(
      'Mercato fair: '
      '${(item.fairMarketProbability * 100).toStringAsFixed(1)}%',
    );

    print(
      'Edge: '
      '${item.edge >= 0 ? '+' : ''}'
      '${(item.edge * 100).toStringAsFixed(1)} p.p.',
    );

    print(
      'EV: '
      '${item.expectedValue >= 0 ? '+' : ''}'
      '${(item.expectedValue * 100).toStringAsFixed(1)}%',
    );

    print(
      'Classificazione: '
      '${item.classification}',
    );

    print('');
  }

  // ============================================================
  // CONVERSIONI
  // ============================================================

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  List<String> _toStringList(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }

  // ============================================================
  // ERROR
  // ============================================================

  AnalysisResult _errorResult(String reason) {
    return AnalysisResult(
      smartScore: 0,

      homeProbability: 0,

      drawProbability: 0,

      awayProbability: 0,

      prediction: 'N/D',

      valueBet: 'N/D',

      risk: 'Dati insufficienti',

      shouldBet: false,

      recommendedStakePercent: 0.0,

      recommendedStakeUnits: 0.0,

      stakeOutcome: '',

      stakeOdd: 0.0,

      stakeBookmaker: '',

      stakeRecommendation: 'Nessuna puntata.',

      explanation:
          '''
SMARTBET AI

ANALISI NON DISPONIBILE

$reason
''',
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _dossierBuilder.dispose();

    _oddsService.dispose();

    _client.close();
  }
}
