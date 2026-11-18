import 'goalvdline_quote_policy.dart';
import 'odds_service.dart';
import 'smartbet_match_simulation_service.dart';

/// Ipotesi sul singolo mercato. NON contiene quote e NON misura la
/// calibrazione storica: la percentuale proviene soltanto dal modello sportivo.
class GoalVdLineSportsAlternative {
  final String market;
  final double probability;

  const GoalVdLineSportsAlternative(this.market, this.probability);
}

/// Una quota osservata nel feed. Non certifica disponibilita sul sito .it.
class GoalVdLineFeedQuotedAlternative {
  final GoalVdLineSportsAlternative sports;
  final double odd;
  final String bookmaker;

  const GoalVdLineFeedQuotedAlternative({
    required this.sports,
    required this.odd,
    required this.bookmaker,
  });

  String get market => sports.market;
  double get probability => sports.probability;
}

class GoalVdLineAlternativeMarketPlan {
  /// L'identita del motore che ha generato QUESTO report.
  /// Non vengono mai mediate previsioni di motori differenti.
  final String engineId;
  final String primaryMarket;
  final double primaryProbability;
  final double? primaryFeedOdd;
  final double dataQuality;
  final List<GoalVdLineSportsAlternative> sportsAlternatives;
  final List<GoalVdLineFeedQuotedAlternative> quotedAlternatives;

  /// Proposta soltanto quando la quota del primario e assente o sotto soglia,
  /// la qualita dati basta e una quota di mercato supera la soglia.
  /// NON inserisce automaticamente una selezione in schedina.
  final GoalVdLineFeedQuotedAlternative? suggestedFallback;
  final String explanation;

  const GoalVdLineAlternativeMarketPlan({
    required this.engineId,
    required this.primaryMarket,
    required this.primaryProbability,
    required this.primaryFeedOdd,
    required this.dataQuality,
    required this.sportsAlternatives,
    required this.quotedAlternatives,
    required this.suggestedFallback,
    required this.explanation,
  });
}

/// Prima fase SHADOW del motore mercati alternativi:
/// 1) riceve una sola previsione e una sola simulazione dello stesso motore;
/// 2) classifica i mercati senza leggere le quote;
/// 3) solo dopo applica il filtro quote osservate nel feed e le soglie.
/// Non combina SmartCore, Diego o il terzo motore e non modifica le loro stime.
class GoalVdLineReliableAlternativeMarketService {
  const GoalVdLineReliableAlternativeMarketService();

  static const double recommendedMinimumProbability = 0.65;
  static const double recommendedMinimumDataQuality = 0.60;

  static const List<String> _standardMarkets = [
    '1', 'X', '2', '1X', 'X2', '12',
    'GOAL', 'NO GOAL',
    'OVER 1.5', 'OVER 2.5', 'OVER 3.5',
    'UNDER 1.5', 'UNDER 2.5', 'UNDER 3.5',
    'MULTIGOL 1-4', 'MULTIGOL 2-4', 'MULTIGOL 2-5',
  ];

  static bool _coherentWithPrimary(String primary, String alternative) {
    // La vittoria in casa non puo essere presentata come lo stesso scenario
    // di una vittoria ospite, di X o di X2, e viceversa.
    if (primary == '1') {
      return !const ['2', 'X', 'X2', 'HCP EURO CASA +1 2']
          .contains(alternative);
    }
    if (primary == '2') {
      return !const ['1', 'X', '1X', 'HCP EURO CASA -1 1']
          .contains(alternative);
    }
    if (primary == 'X') {
      return !const ['1', '2', '12', 'HCP EURO CASA -1 1',
          'HCP EURO CASA +1 2'].contains(alternative);
    }
    return true;
  }

  /// Vincoli di probabilita: l'handicap -1 (1) implica la vittoria (1);
  /// l'handicap +1 (2) implica la vittoria ospite (2). Non stimiamo la
  /// probabilita dal risultato esatto piu probabile: sommiamo TUTTI gli esiti.
  static Map<String, double> _marketDistribution(
    SmartBetSimulationResult simulation,
  ) {
    final values = <String, double>{
      for (final market in _standardMarkets)
        market: simulation.probabilityFor(market),
      for (final market in simulation.marketProbabilities.keys)
        if (market.contains(' O '))
          market: simulation.probabilityFor(market),
    };

    var homeTwo = 0.0;
    var awayTwo = 0.0;
    var homeHandicapMinusOne = 0.0;
    var awayHandicapPlusOne = 0.0;
    for (final score in simulation.exactScores) {
      if (score.homeGoals >= 2) homeTwo += score.probability;
      if (score.awayGoals >= 2) awayTwo += score.probability;
      if (score.homeGoals - score.awayGoals >= 2) {
        homeHandicapMinusOne += score.probability;
      }
      if (score.awayGoals - score.homeGoals >= 2) {
        awayHandicapPlusOne += score.probability;
      }
    }
    values['CASA SEGNA'] = simulation.probabilityFor('HOME SCORES');
    values['OSPITE SEGNA'] = simulation.probabilityFor('AWAY SCORES');
    values['CASA 2+ GOL'] = homeTwo;
    values['OSPITE 2+ GOL'] = awayTwo;
    values['HCP EURO CASA -1 1'] = homeHandicapMinusOne;
    values['HCP EURO CASA +1 2'] = awayHandicapPlusOne;
    return values;
  }

  GoalVdLineAlternativeMarketPlan evaluate({
    required String engineId,
    required String primaryMarket,
    required SmartBetSimulationResult simulation,
    FixtureMarketOdds? odds,
    double minimumProbability = recommendedMinimumProbability,
    double minimumDataQuality = recommendedMinimumDataQuality,
    double minimumOdd = GoalVdLineQuotePolicy.minimumOdd,
  }) {
    if (engineId.trim().isEmpty) {
      throw ArgumentError.value(engineId, 'engineId');
    }
    if (!minimumProbability.isFinite || minimumProbability < 0 ||
        minimumProbability > 1 ||
        !minimumDataQuality.isFinite || minimumDataQuality < 0 ||
        minimumDataQuality > 1 ||
        !minimumOdd.isFinite || minimumOdd < 1) {
      throw ArgumentError('Soglie alternative non valide.');
    }

    final primary = primaryMarket.trim().toUpperCase();
    final distribution = _marketDistribution(simulation);
    final primaryProbability = distribution[primary];
    if (primaryProbability == null) {
      throw ArgumentError.value(primaryMarket, 'primaryMarket',
          'Mercato principale non supportato dal modello di punteggio.');
    }

    // Solo ranking sportivo. Le quote NON decidono chi e piu probabile.
    final ranked = [
      for (final entry in distribution.entries)
        if (entry.key != primary &&
            _coherentWithPrimary(primary, entry.key) &&
            entry.value.isFinite &&
            entry.value > 0 &&
            entry.value <= 1)
          GoalVdLineSportsAlternative(entry.key, entry.value),
    ]..sort((a, b) {
      final p = b.probability.compareTo(a.probability);
      return p != 0 ? p : a.market.compareTo(b.market);
    });

    final primaryQuote = odds?.oddFor(primary);
    final primaryFeedOdd = primaryQuote?.odd;
    final primaryQuoteUsable = primaryFeedOdd != null &&
        primaryFeedOdd.isFinite && primaryFeedOdd > minimumOdd &&
        (primaryQuote?.bookmakerName.trim().isNotEmpty ?? false);
    final goodData = simulation.input.dataQuality >= minimumDataQuality;

    // Quote del feed filtrate sul ranking gia stabilito.
    final quoted = <GoalVdLineFeedQuotedAlternative>[];
    if (goodData && odds != null) {
      for (final sports in ranked) {
        if (sports.probability < minimumProbability) break;
        final quote = odds.oddFor(sports.market);
        if (quote == null || !quote.odd.isFinite ||
            quote.odd <= minimumOdd ||
            quote.bookmakerName.trim().isEmpty) {
          continue;
        }
        quoted.add(GoalVdLineFeedQuotedAlternative(
          sports: sports,
          odd: quote.odd,
          bookmaker: quote.bookmakerName,
        ));
      }
    }

    final fallback = (!primaryQuoteUsable && quoted.isNotEmpty)
        ? quoted.first
        : null;
    final explanation = !goodData
        ? 'Qualita dati insufficiente: nessuna alternativa proposta.'
        : primaryQuoteUsable
        ? 'Il pronostico principale resta disponibile nel feed. '
            'Le alternative sono informative, non sostituzioni automatiche.'
        : fallback == null
        ? 'Pronostico principale invariato. Nessuna alternativa supera '
            'insieme affidabilita stimata e quota disponibile nel feed.'
        : 'Pronostico principale invariato. Il mercato alternativo '
            'selezionato e quello con probabilita sportiva stimata '
            'piu alta tra quelli con quota nel feed superiore alla soglia. '
            'La disponibilita sul sito italiano non e certificata.';

    return GoalVdLineAlternativeMarketPlan(
      engineId: engineId.trim(),
      primaryMarket: primary,
      primaryProbability: primaryProbability,
      primaryFeedOdd: primaryFeedOdd,
      dataQuality: simulation.input.dataQuality,
      sportsAlternatives: List.unmodifiable(ranked),
      quotedAlternatives: List.unmodifiable(quoted),
      suggestedFallback: fallback,
      explanation: explanation,
    );
  }
}
