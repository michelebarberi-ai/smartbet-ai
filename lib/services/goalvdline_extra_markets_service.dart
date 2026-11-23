import 'dart:math' as math;

import '../models/analysis_result.dart';

enum GoalVdLineExtraMarketFamily {
  firstHalf,
  secondHalf,
  totalCorners,
  totalShotsOnTarget,
}

class GoalVdLineExtraMarketEstimate {
  final String market;
  final double? probabilityPercent;
  final bool experimental;
  final String evidence;

  const GoalVdLineExtraMarketEstimate({
    required this.market,
    required this.probabilityPercent,
    required this.experimental,
    required this.evidence,
  });
}

class GoalVdLineVerifiedCountSample {
  /// Only distinct, finished fixture measurements, never bookmaker prices.
  final List<int> totals;
  final int distinctMatchdays;

  const GoalVdLineVerifiedCountSample({
    required this.totals,
    required this.distinctMatchdays,
  });

  bool get qualified => totals.length >= 100 &&
      distinctMatchdays >= 14 &&
      totals.every((value) => value >= 0 && value <= 100);
}

/// Three extra *observational* market families for B78.
///
/// Do not feed into automatic coupon construction or existing AI learning.
/// The initial half-goal split (45% / 55%) is an explicit hypothesis,
/// NOT measured per-league calibration. Corners and shots on target need
/// separate completed-fixture samples, never inferred from xG or odds.
class GoalVdLineExtraMarketsService {
  const GoalVdLineExtraMarketsService();

  static const List<String> firstHalfMarkets = [
    '1T 1', '1T X', '1T 2',
  ];
  static const List<String> secondHalfMarkets = [
    '2T 1', '2T X', '2T 2',
  ];
  static const List<String> cornerMarkets = [
    'CORNER OVER 6.5', 'CORNER UNDER 6.5',
    'CORNER OVER 7.5', 'CORNER UNDER 7.5',
    'CORNER OVER 8.5', 'CORNER UNDER 8.5',
    'CORNER OVER 9.5', 'CORNER UNDER 9.5',
    'CORNER OVER 10.5', 'CORNER UNDER 10.5',
    'CORNER OVER 11.5', 'CORNER UNDER 11.5',
  ];
  static const List<String> shotsOnTargetMarkets = [
    'TIRI PORTA OVER 4.5', 'TIRI PORTA UNDER 4.5',
    'TIRI PORTA OVER 5.5', 'TIRI PORTA UNDER 5.5',
    'TIRI PORTA OVER 6.5', 'TIRI PORTA UNDER 6.5',
    'TIRI PORTA OVER 7.5', 'TIRI PORTA UNDER 7.5',
    'TIRI PORTA OVER 8.5', 'TIRI PORTA UNDER 8.5',
    'TIRI PORTA OVER 9.5', 'TIRI PORTA UNDER 9.5',
  ];

  static const Map<GoalVdLineExtraMarketFamily, List<String>> marketFamilies = {
    GoalVdLineExtraMarketFamily.firstHalf: firstHalfMarkets,
    GoalVdLineExtraMarketFamily.secondHalf: secondHalfMarkets,
    GoalVdLineExtraMarketFamily.totalCorners: cornerMarkets,
    GoalVdLineExtraMarketFamily.totalShotsOnTarget: shotsOnTargetMarkets,
  };

  static bool isExtraMarket(String market) => marketFamilies.values
      .any((family) => family.contains(market.trim().toUpperCase()));

  /// Sporting probabilities only. Neither odds nor a bet selection is used.
  /// Probabilities are scenario estimates and stay outside certified ranking.
  List<GoalVdLineExtraMarketEstimate> halfTimeScenarios(
    AnalysisResult analysis,
  ) {
    final home = analysis.expectedHomeGoals;
    final away = analysis.expectedAwayGoals;
    if (!home.isFinite || !away.isFinite || home <= 0 || away <= 0 ||
        home > 12 || away > 12) {
      return [
        for (final market in [...firstHalfMarkets, ...secondHalfMarkets])
          GoalVdLineExtraMarketEstimate(
            market: market,
            probabilityPercent: null,
            experimental: true,
            evidence: 'xG prepartita non sufficienti',
          ),
      ];
    }

    final first = _periodOneXTwo(home * 0.45, away * 0.45);
    final second = _periodOneXTwo(home * 0.55, away * 0.55);
    return [
      for (var index = 0; index < 3; index++)
        GoalVdLineExtraMarketEstimate(
          market: firstHalfMarkets[index],
          probabilityPercent: first[index],
          experimental: true,
          evidence: 'simulazione primo tempo: quota gol ipotizzata 45%',
        ),
      for (var index = 0; index < 3; index++)
        GoalVdLineExtraMarketEstimate(
          market: secondHalfMarkets[index],
          probabilityPercent: second[index],
          experimental: true,
          evidence: 'simulazione secondo tempo: quota gol ipotizzata 55%',
        ),
    ];
  }

  /// Read-only empirical rates. If coverage is insufficient, no numerical
  /// forecast is shown, to avoid using goal xG as corner/shot probabilities.
  List<GoalVdLineExtraMarketEstimate> countMarketEvidence({
    required GoalVdLineExtraMarketFamily family,
    GoalVdLineVerifiedCountSample? sample,
  }) {
    if (family != GoalVdLineExtraMarketFamily.totalCorners &&
        family != GoalVdLineExtraMarketFamily.totalShotsOnTarget) {
      return const [];
    }
    final qualified = sample?.qualified == true;
    final totals = sample?.totals ?? const <int>[];
    return [
      for (final market in marketFamilies[family]!)
        GoalVdLineExtraMarketEstimate(
          market: market,
          probabilityPercent: qualified
              ? _observedRate(market, totals)
              : null,
          experimental: true,
          evidence: qualified
              ? 'frequenza osservata su ${totals.length} risultati; '
                'non validata fuori campione'
              : 'storico insufficiente: servono 100 partite '
                'concluse e 14 giornate verificate',
        ),
    ];
  }

  double _observedRate(String market, List<int> totals) {
    final parts = market.split(' ');
    final over = parts[parts.length - 2] == 'OVER';
    final line = double.parse(parts.last);
    final hits = totals.where(
      (value) => over ? value > line : value < line,
    ).length;
    return hits * 100.0 / totals.length;
  }

  List<double> _periodOneXTwo(double homeXg, double awayXg) {
    final home = _poisson(homeXg);
    final away = _poisson(awayXg);
    var homeWin = 0.0;
    var draw = 0.0;
    var awayWin = 0.0;
    for (var i = 0; i < home.length; i++) {
      for (var j = 0; j < away.length; j++) {
        final p = home[i] * away[j];
        if (i > j) {
          homeWin += p;
        } else if (i == j) {
          draw += p;
        } else {
          awayWin += p;
        }
      }
    }
    final sum = homeWin + draw + awayWin;
    if (sum <= 0 || !sum.isFinite) return [0, 0, 0];
    return [homeWin, draw, awayWin]
        .map((p) => (p / sum * 100).clamp(0.0, 100.0).toDouble())
        .toList(growable: false);
  }

  List<double> _poisson(double lambda) {
    final probabilities = List<double>.filled(19, 0);
    probabilities[0] = math.exp(-lambda);
    for (var i = 1; i < probabilities.length; i++) {
      probabilities[i] = probabilities[i - 1] * lambda / i;
    }
    return probabilities;
  }
}
