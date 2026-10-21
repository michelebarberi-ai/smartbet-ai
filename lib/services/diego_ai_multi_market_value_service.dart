import '../models/goalvdline_match_engine_models.dart';
import 'diego_ai_market_probability_service.dart';
import 'odds_service.dart';

enum DiegoAiMarketComparisonType { fairMarket, rawImplied }

class DiegoAiMarketValue {
  final String market;

  final double aiProbability;

  final double odd;
  final String bookmaker;

  final double marketProbability;

  final DiegoAiMarketComparisonType comparisonType;

  final double edge;
  final double expectedValue;
  final double diegoFairOdd;

  /// Affidabilità dello specifico mercato, 1-95.
  ///
  /// Per 1/X/2 coincide con la Prediction Confidence DiegoAI.
  /// Per i mercati binari viene calcolata dalla qualità dati
  /// e dalla chiarezza della probabilità dello specifico mercato.
  final int marketConfidence;

  final String classification;

  const DiegoAiMarketValue({
    required this.market,
    required this.aiProbability,
    required this.odd,
    required this.bookmaker,
    required this.marketProbability,
    required this.comparisonType,
    required this.edge,
    required this.expectedValue,
    required this.diegoFairOdd,
    required this.marketConfidence,
    required this.classification,
  });

  bool get hasPositiveEv => expectedValue > 0;

  bool get isSpeculativeValue => classification == 'SPECULATIVE VALUE';

  bool get isQualifiedValue =>
      classification == 'WEAK VALUE' ||
      classification == 'VALUE' ||
      classification == 'STRONG VALUE';

  /// Compatibilità con il codice esistente:
  /// "hasValue" significa value qualificato come raccomandazione.
  bool get hasValue => isQualifiedValue;

  /// Comprende anche il value matematico escluso dalla raccomandazione
  /// perché troppo speculativo.
  bool get hasMathematicalValue => isQualifiedValue || isSpeculativeValue;
}

class DiegoAiMultiMarketValueResult {
  final List<DiegoAiMarketValue> markets;

  const DiegoAiMultiMarketValueResult({required this.markets});

  List<DiegoAiMarketValue> get valueMarkets {
    final result = markets.where((item) => item.isQualifiedValue).toList()
      ..sort((a, b) => b.expectedValue.compareTo(a.expectedValue));

    return List.unmodifiable(result);
  }

  List<DiegoAiMarketValue> get speculativeValueMarkets {
    final result = markets.where((item) => item.isSpeculativeValue).toList()
      ..sort((a, b) => b.expectedValue.compareTo(a.expectedValue));

    return List.unmodifiable(result);
  }

  DiegoAiMarketValue? get bestValue {
    final values = valueMarkets;

    if (values.isEmpty) {
      return null;
    }

    return values.first;
  }

  DiegoAiMarketValue? get bestSpeculativeValue {
    final values = speculativeValueMarkets;

    if (values.isEmpty) {
      return null;
    }

    return values.first;
  }
}

class DiegoAiMultiMarketValueService {
  /// Guardrail iniziale v1.2.1.
  ///
  /// Un value matematico sotto questa probabilità resta informativo,
  /// ma non viene trattato come raccomandazione DiegoAI.
  static const double _speculativeProbabilityThreshold = 0.25;

  final DiegoAiMarketProbabilityService probabilityService;

  const DiegoAiMultiMarketValueService({
    this.probabilityService = const DiegoAiMarketProbabilityService(),
  });

  DiegoAiMultiMarketValueResult calculate({
    required GoalVdLineMatchEngineResult engine,
    required FixtureMarketOdds? odds,
    required int dataConfidence,
    required int predictionConfidence,
  }) {
    if (odds == null) {
      return const DiegoAiMultiMarketValueResult(markets: []);
    }

    final probabilities = probabilityService.asMap(engine);

    final results = <DiegoAiMarketValue>[];

    for (final entry in probabilities.entries) {
      final market = entry.key;
      final aiProbability = entry.value;

      final bestOdd = odds.oddFor(market);

      if (bestOdd == null || bestOdd.odd <= 1.0) {
        continue;
      }

      final fairProbability = _fairProbabilityFor1x2(
        market: market,
        odds: odds.matchWinner,
      );

      final comparisonType = fairProbability != null
          ? DiegoAiMarketComparisonType.fairMarket
          : DiegoAiMarketComparisonType.rawImplied;

      // Per i mercati non 1X2 non costruiamo una falsa
      // probabilità fair usando best odds di bookmaker diversi.
      final marketProbability = fairProbability ?? (1.0 / bestOdd.odd);

      final edge = aiProbability - marketProbability;

      final expectedValue = (aiProbability * bestOdd.odd) - 1.0;

      final diegoFairOdd = aiProbability > 0 ? 1.0 / aiProbability : 0.0;

      final marketConfidence = _marketConfidence(
        market: market,
        probability: aiProbability,
        dataConfidence: dataConfidence,
        predictionConfidence: predictionConfidence,
      );

      final classification = _classify(
        aiProbability: aiProbability,
        dataConfidence: dataConfidence,
        marketConfidence: marketConfidence,
        edge: edge,
        expectedValue: expectedValue,
      );

      results.add(
        DiegoAiMarketValue(
          market: market,
          aiProbability: aiProbability,
          odd: bestOdd.odd,
          bookmaker: bestOdd.bookmakerName,
          marketProbability: marketProbability,
          comparisonType: comparisonType,
          edge: edge,
          expectedValue: expectedValue,
          diegoFairOdd: diegoFairOdd,
          marketConfidence: marketConfidence,
          classification: classification,
        ),
      );
    }

    results.sort((a, b) => b.expectedValue.compareTo(a.expectedValue));

    return DiegoAiMultiMarketValueResult(markets: List.unmodifiable(results));
  }

  double? _fairProbabilityFor1x2({
    required String market,
    required MatchOdds? odds,
  }) {
    if (odds == null || !odds.isComplete) {
      return null;
    }

    switch (market) {
      case '1':
        return odds.fairHomeProbability;
      case 'X':
        return odds.fairDrawProbability;
      case '2':
        return odds.fairAwayProbability;
      default:
        return null;
    }
  }

  int _marketConfidence({
    required String market,
    required double probability,
    required int dataConfidence,
    required int predictionConfidence,
  }) {
    // L'1X2 mantiene la confidence dedicata già validata
    // sul Match Engine.
    if (market == '1' || market == 'X' || market == '2') {
      return predictionConfidence.clamp(1, 95);
    }

    // Nei mercati binari 50% rappresenta massima incertezza.
    //
    // 50% -> clarity 0
    // 75% -> clarity 50
    // 100% -> clarity 100
    final clarity = ((probability - 0.50).abs() / 0.50 * 100.0)
        .clamp(0.0, 100.0)
        .toDouble();

    // Formula validata su 285 osservazioni:
    // 35% qualità dati
    // 65% chiarezza dello specifico mercato
    final confidence = (dataConfidence * 0.35) + (clarity * 0.65);

    return confidence.round().clamp(1, 95);
  }

  String _classify({
    required double aiProbability,
    required int dataConfidence,
    required int marketConfidence,
    required double edge,
    required double expectedValue,
  }) {
    if (dataConfidence < 50 || marketConfidence < 50) {
      return 'NO VALUE';
    }

    String classification;

    if (marketConfidence >= 70 && edge >= 0.08 && expectedValue >= 0.12) {
      classification = 'STRONG VALUE';
    } else if (marketConfidence >= 60 &&
        edge >= 0.05 &&
        expectedValue >= 0.07) {
      classification = 'VALUE';
    } else if (marketConfidence >= 50 &&
        edge >= 0.03 &&
        expectedValue >= 0.04) {
      classification = 'WEAK VALUE';
    } else {
      return 'NO VALUE';
    }

    // Un grande EV non trasforma automaticamente un evento raro
    // in una raccomandazione affidabile.
    if (aiProbability < _speculativeProbabilityThreshold) {
      return 'SPECULATIVE VALUE';
    }

    return classification;
  }
}
