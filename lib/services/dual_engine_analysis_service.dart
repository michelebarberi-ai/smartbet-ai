import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'diego_ai_multi_market_value_service.dart';
import 'diego_ai_service.dart';
import 'smartbet_ai_service.dart';
import 'smartbet_market_probability_service.dart';

String dualEngineMarketLabel(String market) {
  final normalized = market.trim().toUpperCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );

  switch (normalized) {
    case 'CASA 2+ GOL':
      return 'CASA ALMENO 2 GOL';

    case 'OSPITE 2+ GOL':
      return 'OSPITE ALMENO 2 GOL';

    case 'CASA 3+ GOL':
      return 'CASA ALMENO 3 GOL';

    case 'OSPITE 3+ GOL':
      return 'OSPITE ALMENO 3 GOL';

    default:
      return market.trim().toUpperCase();
  }
}

enum DualEngineAgreement { agree, partial, diverge, noSelection, unavailable }

class DualEngineComparison {
  final DualEngineAgreement status;

  final String smartBetMarket;
  final String diegoMarket;

  /// Probabilità interne 0.0 - 1.0.
  final double? smartBetProbability;
  final double? diegoProbability;

  final double? diegoOdd;
  final String? diegoBookmaker;
  final int? diegoMarketConfidence;
  final String? diegoClassification;

  const DualEngineComparison({
    required this.status,
    required this.smartBetMarket,
    required this.diegoMarket,
    this.smartBetProbability,
    this.diegoProbability,
    this.diegoOdd,
    this.diegoBookmaker,
    this.diegoMarketConfidence,
    this.diegoClassification,
  });

  String get label {
    switch (status) {
      case DualEngineAgreement.agree:
        return 'STESSO MERCATO';

      case DualEngineAgreement.partial:
        return 'LETTURE COMPATIBILI';

      case DualEngineAgreement.diverge:
        return 'DIVERGENZA';

      case DualEngineAgreement.noSelection:
        if (diegoClassification == 'SPECULATIVE VALUE') {
          return 'VALUE SPECULATIVO';
        }

        return diegoOdd == null ? 'VALUE NON VERIFICABILE' : 'NESSUN VALUE';

      case DualEngineAgreement.unavailable:
        return 'CONFRONTO NON DISPONIBILE';
    }
  }

  String get description {
    final smartBetLabel = dualEngineMarketLabel(smartBetMarket);

    final diegoLabel = dualEngineMarketLabel(diegoMarket);

    switch (status) {
      case DualEngineAgreement.agree:
        return 'SmartBet e DiegoAI scelgono entrambi '
            '$diegoLabel.';

      case DualEngineAgreement.partial:
        return 'SmartBet sceglie $smartBetLabel mentre '
            'DiegoAI sceglie $diegoLabel. '
            'I mercati sono diversi ma le due letture '
            'possono verificarsi insieme.';

      case DualEngineAgreement.diverge:
        return 'SmartBet sceglie $smartBetLabel mentre '
            'DiegoAI sceglie $diegoLabel. '
            'Le due indicazioni sono in contrasto.';

      case DualEngineAgreement.noSelection:
        if (diegoClassification == 'SPECULATIVE VALUE') {
          return 'DiegoAI rileva valore matematico su $diegoLabel, '
              'ma la probabilità assoluta è troppo bassa per '
              'considerarlo una raccomandazione qualificata.';
        }

        if (diegoOdd == null) {
          return 'DiegoAI indica $diegoLabel come lettura statistica '
              'di riferimento. Il valore non può essere verificato '
              'perché non è disponibile una quota utilizzabile.';
        }

        return 'DiegoAI indica $diegoLabel come lettura statistica '
            'di riferimento, ma non rileva sufficiente valore '
            'nella quota disponibile.';

      case DualEngineAgreement.unavailable:
        return 'DiegoAI non è disponibile per questa partita. '
            'Il risultato SmartBet rimane comunque utilizzabile.';
    }
  }
}

class DualEngineAnalysis {
  final AnalysisResult smartBet;
  final DiegoAiAnalysis? diego;
  final DualEngineComparison comparison;

  const DualEngineAnalysis({
    required this.smartBet,
    required this.diego,
    required this.comparison,
  });
}

class _EngineMarketChoice {
  final String market;
  final double? probability;

  final double? odd;
  final String? bookmaker;
  final int? confidence;
  final String? classification;

  const _EngineMarketChoice({
    required this.market,
    required this.probability,
    this.odd,
    this.bookmaker,
    this.confidence,
    this.classification,
  });
}

/// Punto unico di accesso alle analisi GoalVdLine.
///
/// SmartBet e DiegoAI rimangono completamente indipendenti.
///
/// Ogni motore sceglie il proprio mercato.
/// Il confronto avviene soltanto dopo le due scelte.
///
/// Nessun motore modifica probabilità o decisioni dell'altro.
class DualEngineAnalysisService {
  final SmartBetAiService _smartBetService;
  final DiegoAiService _diegoService;

  DualEngineAnalysisService({
    SmartBetAiService? smartBetService,
    DiegoAiService? diegoService,
  }) : _smartBetService = smartBetService ?? SmartBetAiService(),
       _diegoService = diegoService ?? DiegoAiService();

  /// Analisi completa dei due motori.
  Future<DualEngineAnalysis> analyze(
    MatchModel match, {
    bool runAudit = true,
    bool automaticMode = false,
  }) async {
    final values = await Future.wait<dynamic>([
      _smartBetService.analyzeMatch(
        match,
        runAudit: runAudit,
        automaticMode: automaticMode,
      ),
      _safeDiego(match),
    ]);

    final smartBet = values[0] as AnalysisResult;

    final diego = values[1] as DiegoAiAnalysis?;

    return _build(smartBet: smartBet, diego: diego);
  }

  /// Da usare quando SmartBet è già stato calcolato
  /// o recuperato dalla cache.
  ///
  /// Se la schermata ha già scelto un mercato SmartBet
  /// (es. schedina, risultati, combinazioni) lo passa qui:
  /// il Dual Engine confronterà quella scelta reale con
  /// la scelta indipendente effettuata da DiegoAI.
  Future<DualEngineAnalysis> attachDiego({
    required MatchModel match,
    required AnalysisResult smartBet,
    String? smartBetMarket,
    int? smartBetProbability,
  }) async {
    final diego = await _safeDiego(match);

    return _build(
      smartBet: smartBet,
      diego: diego,
      smartBetMarketOverride: smartBetMarket,
      smartBetProbabilityPercent: smartBetProbability,
    );
  }

  Future<DiegoAiAnalysis?> _safeDiego(MatchModel match) async {
    try {
      return await _diegoService.analyze(match);
    } catch (error, stackTrace) {
      debugPrint('DIEGOAI ANALYSIS ERROR: $error');

      debugPrintStack(stackTrace: stackTrace);

      return null;
    }
  }

  DualEngineAnalysis _build({
    required AnalysisResult smartBet,
    required DiegoAiAnalysis? diego,
    String? smartBetMarketOverride,
    int? smartBetProbabilityPercent,
  }) {
    final smartChoice = _smartBetChoice(
      smartBet,
      marketOverride: smartBetMarketOverride,
      probabilityPercentOverride: smartBetProbabilityPercent,
    );

    if (diego == null) {
      return DualEngineAnalysis(
        smartBet: smartBet,
        diego: null,
        comparison: DualEngineComparison(
          status: DualEngineAgreement.unavailable,
          smartBetMarket: smartChoice.market,
          diegoMarket: 'N/D',
          smartBetProbability: smartChoice.probability,
        ),
      );
    }

    final diegoChoice = _diegoChoice(diego);

    if (diegoChoice == null) {
      final statisticalChoice = _diegoStatisticalChoice(diego);

      return DualEngineAnalysis(
        smartBet: smartBet,
        diego: diego,
        comparison: DualEngineComparison(
          status: DualEngineAgreement.noSelection,
          smartBetMarket: smartChoice.market,
          diegoMarket: statisticalChoice.market,
          smartBetProbability: smartChoice.probability,
          diegoProbability: statisticalChoice.probability,
          diegoOdd: statisticalChoice.odd,
          diegoBookmaker: statisticalChoice.bookmaker,
          diegoMarketConfidence: statisticalChoice.confidence,
          diegoClassification: statisticalChoice.classification ?? 'NO VALUE',
        ),
      );
    }

    return DualEngineAnalysis(
      smartBet: smartBet,
      diego: diego,
      comparison: DualEngineComparison(
        status: _agreement(
          smartBetMarket: smartChoice.market,
          diegoMarket: diegoChoice.market,
        ),
        smartBetMarket: smartChoice.market,
        diegoMarket: diegoChoice.market,
        smartBetProbability: smartChoice.probability,
        diegoProbability: diegoChoice.probability,
        diegoOdd: diegoChoice.odd,
        diegoBookmaker: diegoChoice.bookmaker,
        diegoMarketConfidence: diegoChoice.confidence,
        diegoClassification: diegoChoice.classification,
      ),
    );
  }

  _EngineMarketChoice _smartBetChoice(
    AnalysisResult result, {
    String? marketOverride,
    int? probabilityPercentOverride,
  }) {
    if (marketOverride != null && marketOverride.trim().isNotEmpty) {
      final market = _normalizeMarket(marketOverride);

      final probability = probabilityPercentOverride != null
          ? (probabilityPercentOverride.clamp(0, 100) / 100.0).toDouble()
          : _smartBetProbabilityFor(result, market);

      return _EngineMarketChoice(market: market, probability: probability);
    }

    final market = _smartBetMarketFromPrediction(result);

    return _EngineMarketChoice(
      market: market,
      probability: _smartBetProbabilityFor(result, market),
    );
  }

  String _smartBetMarketFromPrediction(AnalysisResult result) {
    final raw = _normalizeMarket(result.prediction);

    for (final market in _recognizableMarkets) {
      if (raw == market ||
          raw.startsWith('$market ') ||
          raw.startsWith('$market-') ||
          raw.startsWith('$market:') ||
          raw.startsWith('$market(') ||
          raw.startsWith('$market•')) {
        return market;
      }
    }

    // Se prediction contiene testo descrittivo.
    for (final market in _recognizableMarkets) {
      if (market.length > 1 && raw.contains(market)) {
        return market;
      }
    }

    // Fallback 1X2.
    if (result.homeProbability >= result.drawProbability &&
        result.homeProbability >= result.awayProbability) {
      return '1';
    }

    if (result.drawProbability >= result.homeProbability &&
        result.drawProbability >= result.awayProbability) {
      return 'X';
    }

    return '2';
  }

  double? _smartBetProbabilityFor(AnalysisResult result, String market) {
    final key = _normalizeMarket(market);

    final percent = switch (key) {
      '1' => result.homeProbability,

      'X' => result.drawProbability,

      '2' => result.awayProbability,

      '1X' => (result.homeProbability + result.drawProbability).clamp(0, 100),

      'X2' => (result.drawProbability + result.awayProbability).clamp(0, 100),

      '12' => (result.homeProbability + result.awayProbability).clamp(0, 100),

      'OVER 1.5' => result.over15Probability,

      'UNDER 1.5' => result.under15Probability,

      'OVER 2.5' => result.over25Probability,

      'UNDER 2.5' => result.under25Probability,

      'GOAL' => result.goalProbability,

      'NO GOAL' => result.noGoalProbability,

      _ => SmartBetMarketProbabilityService.probabilityFor(result, key),
    };

    if (percent <= 0) {
      return null;
    }

    return (percent / 100.0).clamp(0.0, 1.0).toDouble();
  }

  _EngineMarketChoice? _diegoChoice(DiegoAiAnalysis analysis) {
    // DiegoAI presenta una vera selezione soltanto quando
    // il Value Engine identifica:
    // WEAK VALUE / VALUE / STRONG VALUE.
    //
    // Un mercato NO VALUE resta informazione statistica,
    // ma non viene mostrato come raccomandazione.
    final bestValue = analysis.bestMultiMarketValue;

    if (bestValue == null) {
      return null;
    }

    return _choiceFromValue(bestValue);
  }

  _EngineMarketChoice _diegoStatisticalChoice(DiegoAiAnalysis analysis) {
    // Se esiste un value matematico escluso soltanto perché
    // troppo speculativo, lo mostriamo come LETTURA e non
    // come raccomandazione DiegoAI.
    final speculativeValue = analysis.multiMarketValue.bestSpeculativeValue;

    if (speculativeValue != null) {
      return _choiceFromValue(speculativeValue);
    }

    // Se esistono mercati con quota, prendiamo quello
    // che Diego considera statisticamente più probabile.
    //
    // In questo ramo nessuno di questi mercati ha superato
    // il filtro Value, quindi resta una LETTURA STATISTICA
    // e non una raccomandazione di giocata.
    final quotedMarkets = analysis.multiMarketValue.markets;

    if (quotedMarkets.isNotEmpty) {
      final ranked = [...quotedMarkets]
        ..sort((a, b) => b.aiProbability.compareTo(a.aiProbability));

      return _choiceFromValue(ranked.first);
    }

    // Se non ci sono quote multi-mercato disponibili,
    // mostriamo comunque la lettura 1X2 più probabile.
    final oneXTwo = <_EngineMarketChoice>[
      _EngineMarketChoice(
        market: '1',
        probability: analysis.homeProbability,
        classification: 'VALUE NON VERIFICABILE',
      ),
      _EngineMarketChoice(
        market: 'X',
        probability: analysis.drawProbability,
        classification: 'VALUE NON VERIFICABILE',
      ),
      _EngineMarketChoice(
        market: '2',
        probability: analysis.awayProbability,
        classification: 'VALUE NON VERIFICABILE',
      ),
    ]..sort((a, b) => (b.probability ?? 0.0).compareTo(a.probability ?? 0.0));

    return oneXTwo.first;
  }

  _EngineMarketChoice _choiceFromValue(DiegoAiMarketValue value) {
    return _EngineMarketChoice(
      market: _normalizeMarket(value.market),
      probability: value.aiProbability,
      odd: value.odd,
      bookmaker: value.bookmaker,
      confidence: value.marketConfidence,
      classification: value.classification,
    );
  }

  DualEngineAgreement _agreement({
    required String smartBetMarket,
    required String diegoMarket,
  }) {
    final smart = _normalizeMarket(smartBetMarket);

    final diego = _normalizeMarket(diegoMarket);

    if (smart == diego) {
      return DualEngineAgreement.agree;
    }

    if (_areContradictory(smart, diego)) {
      return DualEngineAgreement.diverge;
    }

    return DualEngineAgreement.partial;
  }

  bool _areContradictory(String a, String b) {
    // ==========================================================
    // 1X2 / DOPPIA CHANCE
    // ==========================================================

    const resultSets = <String, Set<String>>{
      '1': {'1'},
      'X': {'X'},
      '2': {'2'},
      '1X': {'1', 'X'},
      'X2': {'X', '2'},
      '12': {'1', '2'},
    };

    final setA = resultSets[a];
    final setB = resultSets[b];

    if (setA != null && setB != null) {
      return setA.intersection(setB).isEmpty;
    }

    // ==========================================================
    // GOAL / NO GOAL
    // ==========================================================

    if ((a == 'GOAL' && b == 'NO GOAL') || (a == 'NO GOAL' && b == 'GOAL')) {
      return true;
    }

    // ==========================================================
    // CHI SEGNA PRIMA
    // ==========================================================

    if ((a == 'CASA SEGNA PRIMA' && b == 'OSPITE SEGNA PRIMA') ||
        (a == 'OSPITE SEGNA PRIMA' && b == 'CASA SEGNA PRIMA')) {
      return true;
    }

    // ==========================================================
    // OVER / UNDER
    // ==========================================================

    final goalLineA = _goalLine(a);

    final goalLineB = _goalLine(b);

    if (goalLineA != null &&
        goalLineB != null &&
        goalLineA.key != goalLineB.key) {
      final overLine = goalLineA.key == 'OVER'
          ? goalLineA.value
          : goalLineB.value;

      final underLine = goalLineA.key == 'UNDER'
          ? goalLineA.value
          : goalLineB.value;

      // OVER 1.5 + UNDER 2.5 sono compatibili:
      // esattamente 2 gol.
      //
      // OVER 2.5 + UNDER 2.5 sono incompatibili.
      return overLine >= underLine;
    }

    // ==========================================================
    // COMBO GOAL + OVER
    // ==========================================================

    if (_comboGoalOverContradicts(a, b) || _comboGoalOverContradicts(b, a)) {
      return true;
    }

    if (_comboNoGoalUnderContradicts(a, b) ||
        _comboNoGoalUnderContradicts(b, a)) {
      return true;
    }

    return false;
  }

  bool _comboGoalOverContradicts(String combo, String other) {
    if (combo != 'GOAL + O2.5') {
      return false;
    }

    if (other == 'NO GOAL' || other == 'NO GOAL + U2.5') {
      return true;
    }

    final line = _goalLine(other);

    return line != null && line.key == 'UNDER' && line.value <= 2.5;
  }

  bool _comboNoGoalUnderContradicts(String combo, String other) {
    if (combo != 'NO GOAL + U2.5') {
      return false;
    }

    if (other == 'GOAL' || other == 'GOAL + O2.5') {
      return true;
    }

    final line = _goalLine(other);

    return line != null && line.key == 'OVER' && line.value >= 2.5;
  }

  MapEntry<String, double>? _goalLine(String market) {
    final match = RegExp(
      r'^(OVER|UNDER) ([0-9]+(?:\.[0-9]+)?)$',
    ).firstMatch(market);

    if (match == null) {
      return null;
    }

    final side = match.group(1);
    final rawLine = match.group(2);

    if (side == null || rawLine == null) {
      return null;
    }

    final line = double.tryParse(rawLine);

    if (line == null) {
      return null;
    }

    return MapEntry(side, line);
  }

  String _normalizeMarket(String value) {
    var normalized = value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

    normalized = normalized
        .replaceAll('NOGOAL', 'NO GOAL')
        .replaceAll('BTTS YES', 'GOAL')
        .replaceAll('BTTS NO', 'NO GOAL');

    return normalized;
  }

  static const List<String> _recognizableMarkets = [
    'NO GOAL + U2.5',
    'GOAL + O2.5',
    'CASA SEGNA PRIMA',
    'OSPITE SEGNA PRIMA',
    'CASA 3+ GOL',
    'OSPITE 3+ GOL',
    'CASA 2+ GOL',
    'OSPITE 2+ GOL',
    'CASA SEGNA',
    'OSPITE SEGNA',
    'UNDER 4.5',
    'OVER 4.5',
    'UNDER 3.5',
    'OVER 3.5',
    'UNDER 2.5',
    'OVER 2.5',
    'UNDER 1.5',
    'OVER 1.5',
    'NO GOAL',
    'GOAL',
    '1X',
    'X2',
    '12',
    '1',
    'X',
    '2',
  ];

  void dispose() {
    _smartBetService.dispose();
    _diegoService.dispose();
  }
}
