import 'smartbet_analysis_history_store.dart';
import 'smartbet_league_market_reliability_service.dart';
import 'goalvdline_quote_policy.dart';

/// Audit B78 of a sporting ranking. Prices are an output-only diagnostic,
/// NEVER an input to ranking, historical calibration or AI predictions.
class GoalVdLineMarketOpportunity {
  final String market;
  final double modelProbabilityPercent;
  final double? actualOdd;
  final double? impliedProbabilityPercent;
  final double? nominalEdgePoints;
  final SmartBetLeagueMarketReliability? evidence;
  final bool evidenceIsQualified;
  final String assessment;

  const GoalVdLineMarketOpportunity({
    required this.market,
    required this.modelProbabilityPercent,
    required this.actualOdd,
    required this.impliedProbabilityPercent,
    required this.nominalEdgePoints,
    required this.evidence,
    required this.evidenceIsQualified,
    required this.assessment,
  });
}

class GoalVdLineMarketOpportunityReport {
  final List<GoalVdLineMarketOpportunity> rankedSportingMarkets;
  final String? selectedMarket;
  final bool selectedMarketIsTopSporting;
  final bool hasVerifiedValueCandidate;

  const GoalVdLineMarketOpportunityReport({
    required this.rankedSportingMarkets,
    required this.selectedMarket,
    required this.selectedMarketIsTopSporting,
    required this.hasVerifiedValueCandidate,
  });

  GoalVdLineMarketOpportunity? get selected {
    for (final item in rankedSportingMarkets) {
      if (item.market.trim().toUpperCase() ==
          selectedMarket?.trim().toUpperCase()) return item;
    }
    return null;
  }
}

/// Read-only guard: displays why an apparently easy price might be unsafe.
/// A positive edge computed from an *uncalibrated* model is not evidence
/// of betting value or a reason to add a fixture to a multiple.
class GoalVdLineMarketOpportunityService {
  const GoalVdLineMarketOpportunityService();

  static const int minimumQualifiedFixtures = 100;
  static const int minimumQualifiedDays = 14;
  static const double minimumNominalMarginPoints = 5.0;

  GoalVdLineMarketOpportunityReport compare({
    required Map<String, double> sportingPercent,
    required String country,
    required String league,
    SmartBetAnalysisEngine engine = SmartBetAnalysisEngine.smartBet,
    SmartBetLeagueMarketReliabilityReport? history,
    Map<String, double> quotedOdds = const {},
    String? selectedMarket,
  }) {
    // No sorting by odds, payout, historical hit-rate or profitability.
    final candidates = sportingPercent.entries.where((entry) =>
        entry.key.trim().isNotEmpty &&
        entry.value.isFinite &&
        entry.value > 0.0 &&
        entry.value <= 100.0).toList()
      ..sort((a, b) {
        final p = b.value.compareTo(a.value);
        return p != 0 ? p : a.key.compareTo(b.key);
      });

    final options = <GoalVdLineMarketOpportunity>[];
    for (final entry in candidates) {
      final evidence = history?.find(
        engine: engine, country: country, league: league,
        market: entry.key,
      );
      final qualified = evidence != null &&
          evidence.sampleSize >= minimumQualifiedFixtures &&
          evidence.distinctMatchDays >= minimumQualifiedDays &&
          evidence.probabilitySampleSize == evidence.sampleSize &&
          evidence.brierScore != null &&
          evidence.calibrationGapPoints != null;

      final quoted = quotedOdds[entry.key];
      final odd = quoted != null && quoted.isFinite && quoted > 1
          ? quoted : null;
      final implied = odd == null ? null : 100.0 / odd;
      final edge = implied == null ? null : entry.value - implied;

      String verdict;
      if (odd == null) {
        verdict = 'Quota reale non disponibile: valore non verificabile';
      } else if (!GoalVdLineQuotePolicy.isPlayable(odd)) {
        verdict = 'Quota non superiore a 1,20: non giocabile';
      } else if (edge != null && edge <= 0) {
        verdict = 'Quota apparentemente facile, stima AI sotto il pareggio';
      } else if (!qualified) {
        verdict = 'Dati storici insufficienti: vantaggio non dimostrato';
      } else if (evidence.calibrationGapPoints! < -5) {
        verdict = 'Storico: il modello tende a sovrastimare questo mercato';
      } else if (edge != null && edge < minimumNominalMarginPoints) {
        verdict = 'Margine nominale troppo piccolo per confermare valore';
      } else {
        verdict = 'Margine solo indicativo: verifica calibrazione e bookmaker';
      }

      options.add(GoalVdLineMarketOpportunity(
        market: entry.key,
        modelProbabilityPercent: entry.value,
        actualOdd: odd,
        impliedProbabilityPercent: implied,
        nominalEdgePoints: edge,
        evidence: evidence,
        evidenceIsQualified: qualified,
        assessment: verdict,
      ));
    }
    final selectedNormalized = selectedMarket?.trim().toUpperCase();
    final top = options.isEmpty ? null : options.first.market.toUpperCase();
    return GoalVdLineMarketOpportunityReport(
      rankedSportingMarkets: List.unmodifiable(options),
      selectedMarket: selectedMarket,
      selectedMarketIsTopSporting: top != null &&
          top == selectedNormalized,
      // No automatic 'safe' approval until a prospective,
      // out-of-sample calibration gate is implemented.
      hasVerifiedValueCandidate: false,
    );
  }
}
