import '../models/analysis_result.dart';
import 'odds_service.dart';
import 'goalvdline_quote_policy.dart';
import 'smartbet_european_handicap_candidate_service.dart';
import 'smartbet_market_probability_service.dart';
import 'smartbet_refundable_market_candidate_service.dart';

class SmartBetMultiMarketOption {
  final String market;
  final int probability;
  final double? odd;
  final String? bookmaker;

  const SmartBetMultiMarketOption({
    required this.market,
    required this.probability,
    this.odd,
    this.bookmaker,
  });
}

class SmartBetMultiMarketPick {
  final String market;
  final int probability;
  final double odd;
  final String bookmaker;
  final List<SmartBetMultiMarketOption> options;

  const SmartBetMultiMarketPick({
    required this.market,
    required this.probability,
    required this.odd,
    required this.bookmaker,
    required this.options,
  });
}

/// P19C: 1-3 famiglie contemporanee nelle Combinazioni AI.
/// Ranking sportivo indipendente dalle quote, usate solo come filtro finale.
class SmartBetMultiMarketSelectionService {
  const SmartBetMultiMarketSelectionService._();

  static const List<String> selectable = [
    '1',
    'X',
    '2',
    '1X',
    'X2',
    '12',
    'OVER',
    'UNDER',
    'GOAL',
    'NO GOAL',
    'CASA SEGNA',
    'OSPITE SEGNA',
    'HANDICAP EUROPEO',
    'MULTIGOL',
    'COMBO AVANZATE',
    'DRAW NO BET',
    'HANDICAP ASIATICO',
  ];

  static List<String> _validate(Iterable<String> families) {
    final selected = families.toSet().toList(growable: false);
    if (selected.isEmpty ||
        selected.length > 3 ||
        selected.any((family) => !selectable.contains(family))) {
      throw ArgumentError('Scegliere da 1 a 3 famiglie quotabili.');
    }
    return selected;
  }

  static List<String> _options(String family) {
    switch (family) {
      case 'OVER':
        return const ['OVER 1.5', 'OVER 2.5', 'OVER 3.5', 'OVER 4.5'];
      case 'UNDER':
        return const ['UNDER 1.5', 'UNDER 2.5', 'UNDER 3.5', 'UNDER 4.5'];
      case 'CASA SEGNA':
        return const [
          'CASA SEGNA',
          'CASA SEGNA PRIMA',
          'CASA 2+ GOL',
          'CASA 3+ GOL',
        ];
      case 'OSPITE SEGNA':
        return const [
          'OSPITE SEGNA',
          'OSPITE SEGNA PRIMA',
          'OSPITE 2+ GOL',
          'OSPITE 3+ GOL',
        ];
      case 'HANDICAP EUROPEO':
      case 'HANDICAP ASIATICO':
        return const [];
      case 'DRAW NO BET':
        return SmartBetRefundableMarketCandidateService.drawNoBet;
      case 'MULTIGOL':
        return const [
          'MULTIGOL 1-4',
          'MULTIGOL 2-4',
          'MULTIGOL 2-5',
          'MULTIGOL 3-5',
        ];
      case 'COMBO AVANZATE':
        return const [
          '1X + O1.5',
          'X2 + O1.5',
          '1X + U3.5',
          'X2 + U3.5',
          '1 + O1.5',
          '2 + O1.5',
          '1 + U3.5',
          '2 + U3.5',
          '1X + O2.5',
          'X2 + O2.5',
          '1X + U2.5',
          'X2 + U2.5',
          'GOAL + O2.5',
          'NO GOAL + U2.5',
        ];
      default:
        return [family];
    }
  }

  static int _probability(AnalysisResult result, String market) {
    switch (market) {
      case 'DNB CASA':
      case 'DNB OSPITE':
        return SmartBetRefundableMarketCandidateService.drawNoBetProbability(
          result,
          market,
        );
      case '1':
        return result.homeProbability;
      case 'X':
        return result.drawProbability;
      case '2':
        return result.awayProbability;
      case '1X':
        return (result.homeProbability + result.drawProbability).clamp(0, 100);
      case 'X2':
        return (result.drawProbability + result.awayProbability).clamp(0, 100);
      case '12':
        return (result.homeProbability + result.awayProbability).clamp(0, 100);
      case 'OVER 1.5':
        return result.over15Probability;
      case 'UNDER 1.5':
        return result.under15Probability;
      case 'OVER 2.5':
        return result.over25Probability;
      case 'UNDER 2.5':
        return result.under25Probability;
      case 'GOAL':
        return result.goalProbability;
      case 'NO GOAL':
        return result.noGoalProbability;
      default:
        return SmartBetMarketProbabilityService.probabilityFor(result, market);
    }
  }

  static int searchProbability({
    required AnalysisResult analysis,
    required Iterable<String> families,
  }) {
    final selected = _validate(families);
    var best = 0;
    for (final family in selected) {
      if (family == 'HANDICAP ASIATICO') {
        final proxy = SmartBetRefundableMarketCandidateService.searchProxy(
          analysis,
        );
        if (proxy > best) best = proxy;
        continue;
      }
      if (family == 'HANDICAP EUROPEO') {
        // Soltanto proxy sportivo per la shortlist, NON una stima handicap.
        final proxy = [
          analysis.homeProbability,
          analysis.drawProbability,
          analysis.awayProbability,
        ].reduce((a, b) => a > b ? a : b);
        if (proxy > best) best = proxy;
        continue;
      }
      for (final option in _options(family)) {
        final value = _probability(analysis, option);
        if (value > best) best = value;
      }
    }
    return best;
  }

  static SmartBetMultiMarketPick? bestQuoted({
    required AnalysisResult analysis,
    required FixtureMarketOdds odds,
    required Iterable<String> families,
    double minimumOdd = GoalVdLineQuotePolicy.minimumOdd,
  }) {
    final selected = _validate(families);
    final options = <SmartBetMultiMarketOption>[];
    final seen = <String>{};
    String? bestMarket;
    int bestProbability = -1;
    BestOdd? bestOdd;

    for (final family in selected) {
      final handicap = family == 'HANDICAP EUROPEO'
          ? SmartBetEuropeanHandicapCandidateService.candidates(
              expectedHomeGoals: analysis.expectedHomeGoals,
              expectedAwayGoals: analysis.expectedAwayGoals,
              quotedOutcomes: odds.bestByOutcome.keys,
            )
          : const <({String market, int probability})>[];
      final asian = family == 'HANDICAP ASIATICO'
          ? SmartBetRefundableMarketCandidateService.asianCandidates(
              analysis: analysis,
              quotedOutcomes: odds.bestByOutcome.keys,
            )
          : const <({String market, int probability})>[];
      final handicapProbs = <String, int>{
        for (final option in handicap) option.market: option.probability,
        for (final option in asian) option.market: option.probability,
      };
      final markets =
          family == 'HANDICAP EUROPEO' || family == 'HANDICAP ASIATICO'
          ? handicapProbs.keys
          : _options(family);
      for (final market in markets) {
        if (!seen.add(market)) continue;
        final probability =
            family == 'HANDICAP EUROPEO' || family == 'HANDICAP ASIATICO'
            ? (handicapProbs[market] ?? 0)
            : _probability(analysis, market);
        final quote = odds.oddFor(market);
        options.add(
          SmartBetMultiMarketOption(
            market: market,
            probability: probability,
            odd: quote?.odd,
            bookmaker: quote?.bookmakerName,
          ),
        );
        // Le quote non aumentano lo score e non risolvono pareggi:
        // servono soltanto a verificare l'effettiva giocabilità.
        if (probability <= 0 ||
            quote == null ||
            !quote.odd.isFinite ||
            quote.odd <= minimumOdd) {
          continue;
        }
        if (probability > bestProbability) {
          bestMarket = market;
          bestProbability = probability;
          bestOdd = quote;
        }
      }
    }
    if (bestMarket == null || bestOdd == null) return null;
    return SmartBetMultiMarketPick(
      market: bestMarket,
      probability: bestProbability,
      odd: bestOdd.odd,
      bookmaker: bestOdd.bookmakerName,
      options: List.unmodifiable(options),
    );
  }
}
