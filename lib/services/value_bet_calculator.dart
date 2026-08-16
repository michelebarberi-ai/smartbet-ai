import 'odds_service.dart';

// ============================================================
// ANALISI SINGOLO ESITO
// ============================================================

class ValueBetOutcome {
  final String outcome;

  // Migliore quota realmente disponibile.
  final double bestOdd;

  final int bookmakerId;

  final String bookmakerName;

  // Probabilità SmartBet.
  final double aiProbability;

  // Probabilità fair derivata dal bookmaker
  // di riferimento, NON dalle best odds.
  final double fairMarketProbability;

  // Differenza:
  //
  // P_AI - P_MARKET_FAIR
  final double edge;

  // EV calcolato sulla BEST ODDS.
  final double expectedValue;

  // Quota equa secondo SmartBet.
  final double smartBetFairOdd;

  final String classification;

  const ValueBetOutcome({
    required this.outcome,
    required this.bestOdd,
    required this.bookmakerId,
    required this.bookmakerName,
    required this.aiProbability,
    required this.fairMarketProbability,
    required this.edge,
    required this.expectedValue,
    required this.smartBetFairOdd,
    required this.classification,
  });

  bool get hasValue {
    return classification == 'WEAK VALUE' ||
        classification == 'VALUE' ||
        classification == 'STRONG VALUE';
  }
}

// ============================================================
// RISULTATO COMPLETO
// ============================================================

class ValueBetResult {
  final bool oddsAvailable;

  final String referenceBookmaker;

  final double referenceMargin;

  final ValueBetOutcome? home;

  final ValueBetOutcome? draw;

  final ValueBetOutcome? away;

  final ValueBetOutcome? bestValue;

  final String label;

  final String explanation;

  const ValueBetResult({
    required this.oddsAvailable,
    required this.referenceBookmaker,
    required this.referenceMargin,
    required this.home,
    required this.draw,
    required this.away,
    required this.bestValue,
    required this.label,
    required this.explanation,
  });

  factory ValueBetResult.noOdds() {
    return const ValueBetResult(
      oddsAvailable: false,
      referenceBookmaker: '',
      referenceMargin: 0.0,
      home: null,
      draw: null,
      away: null,
      bestValue: null,
      label: 'NO',
      explanation: 'Quote 1X2 pre-match non disponibili.',
    );
  }
}

// ============================================================
// VALUE BET CALCULATOR
// ============================================================

class ValueBetCalculator {
  const ValueBetCalculator();

  ValueBetResult calculate({
    required int homeProbability,
    required int drawProbability,
    required int awayProbability,
    required int dataConfidence,
    required MatchOdds? odds,
  }) {
    // ==========================================================
    // QUOTE
    // ==========================================================

    if (odds == null || !odds.isComplete) {
      return ValueBetResult.noOdds();
    }

    // ==========================================================
    // VALIDAZIONE PROBABILITÀ
    // ==========================================================

    final total = homeProbability + drawProbability + awayProbability;

    if (total != 100) {
      return ValueBetResult(
        oddsAvailable: true,
        referenceBookmaker: odds.referenceMarket.bookmakerName,
        referenceMargin: odds.bookmakerMargin,
        home: null,
        draw: null,
        away: null,
        bestValue: null,
        label: 'NO',
        explanation: 'Probabilità SmartBet non valide.',
      );
    }

    // ==========================================================
    // ESITO 1
    // ==========================================================

    final home = _buildOutcome(
      outcome: '1',
      bestOdd: odds.bestHome,
      aiProbability: homeProbability / 100.0,
      fairMarketProbability: odds.fairHomeProbability,
      dataConfidence: dataConfidence,
    );

    // ==========================================================
    // ESITO X
    // ==========================================================

    final draw = _buildOutcome(
      outcome: 'X',
      bestOdd: odds.bestDraw,
      aiProbability: drawProbability / 100.0,
      fairMarketProbability: odds.fairDrawProbability,
      dataConfidence: dataConfidence,
    );

    // ==========================================================
    // ESITO 2
    // ==========================================================

    final away = _buildOutcome(
      outcome: '2',
      bestOdd: odds.bestAway,
      aiProbability: awayProbability / 100.0,
      fairMarketProbability: odds.fairAwayProbability,
      dataConfidence: dataConfidence,
    );

    // ==========================================================
    // VALUE CANDIDATES
    // ==========================================================

    final candidates = [
      home,
      draw,
      away,
    ].where((item) => item.hasValue).toList();

    // Migliore value:
    // ordiniamo per EV reale sulla best odd.

    candidates.sort((a, b) => b.expectedValue.compareTo(a.expectedValue));

    final ValueBetOutcome? bestValue = candidates.isEmpty
        ? null
        : candidates.first;

    // ==========================================================
    // NO VALUE
    // ==========================================================

    if (bestValue == null) {
      return ValueBetResult(
        oddsAvailable: true,
        referenceBookmaker: odds.referenceMarket.bookmakerName,
        referenceMargin: odds.bookmakerMargin,
        home: home,
        draw: draw,
        away: away,
        bestValue: null,
        label: 'NO',
        explanation:
            'Nessun esito supera le soglie SmartBet '
            'di edge ed expected value.',
      );
    }

    // ==========================================================
    // DESCRIZIONE MIGLIOR VALUE
    // ==========================================================

    final aiPercent = bestValue.aiProbability * 100.0;

    final marketPercent = bestValue.fairMarketProbability * 100.0;

    final edgePercent = bestValue.edge * 100.0;

    final evPercent = bestValue.expectedValue * 100.0;

    final fairOdd = bestValue.smartBetFairOdd;

    final explanation =
        '${bestValue.classification} '
        '${bestValue.outcome} '
        '@ ${bestValue.bestOdd.toStringAsFixed(2)} '
        '(${bestValue.bookmakerName}) | '
        'AI ${aiPercent.toStringAsFixed(1)}% | '
        'Mercato fair ${marketPercent.toStringAsFixed(1)}% | '
        'Quota equa SmartBet ${fairOdd.toStringAsFixed(2)} | '
        'Edge ${edgePercent >= 0 ? '+' : ''}'
        '${edgePercent.toStringAsFixed(1)} p.p. | '
        'EV ${evPercent >= 0 ? '+' : ''}'
        '${evPercent.toStringAsFixed(1)}%';

    return ValueBetResult(
      oddsAvailable: true,
      referenceBookmaker: odds.referenceMarket.bookmakerName,
      referenceMargin: odds.bookmakerMargin,
      home: home,
      draw: draw,
      away: away,
      bestValue: bestValue,
      label: bestValue.classification,
      explanation: explanation,
    );
  }

  // ============================================================
  // COSTRUZIONE ESITO
  // ============================================================

  ValueBetOutcome _buildOutcome({
    required String outcome,
    required BestOdd bestOdd,
    required double aiProbability,
    required double fairMarketProbability,
    required int dataConfidence,
  }) {
    // ==========================================================
    // EDGE
    // ==========================================================

    final double edge = aiProbability - fairMarketProbability;

    // ==========================================================
    // EXPECTED VALUE
    // ==========================================================
    //
    // EV utilizza la MIGLIORE quota realmente disponibile.
    //
    // EV = (P_AI × quota) - 1
    // ==========================================================

    final double expectedValue = (aiProbability * bestOdd.odd) - 1.0;

    // ==========================================================
    // QUOTA EQUA SMARTBET
    // ==========================================================

    final double smartBetFairOdd = aiProbability > 0.0
        ? 1.0 / aiProbability
        : 0.0;

    // ==========================================================
    // CLASSIFICAZIONE
    // ==========================================================

    final classification = _classify(
      edge: edge,
      expectedValue: expectedValue,
      confidence: dataConfidence,
    );

    return ValueBetOutcome(
      outcome: outcome,
      bestOdd: bestOdd.odd,
      bookmakerId: bestOdd.bookmakerId,
      bookmakerName: bestOdd.bookmakerName,
      aiProbability: aiProbability,
      fairMarketProbability: fairMarketProbability,
      edge: edge,
      expectedValue: expectedValue,
      smartBetFairOdd: smartBetFairOdd,
      classification: classification,
    );
  }

  // ============================================================
  // CLASSIFICAZIONE
  // ============================================================

  String _classify({
    required double edge,
    required double expectedValue,
    required int confidence,
  }) {
    // ----------------------------------------------------------
    // CONFIDENCE TROPPO BASSA
    // ----------------------------------------------------------

    if (confidence < 50) {
      return 'NO VALUE';
    }

    // ----------------------------------------------------------
    // STRONG VALUE
    // ----------------------------------------------------------

    if (confidence >= 70 && edge >= 0.08 && expectedValue >= 0.12) {
      return 'STRONG VALUE';
    }

    // ----------------------------------------------------------
    // VALUE
    // ----------------------------------------------------------

    if (confidence >= 60 && edge >= 0.05 && expectedValue >= 0.07) {
      return 'VALUE';
    }

    // ----------------------------------------------------------
    // WEAK VALUE
    // ----------------------------------------------------------

    if (confidence >= 55 && edge >= 0.03 && expectedValue >= 0.04) {
      return 'WEAK VALUE';
    }

    return 'NO VALUE';
  }
}
