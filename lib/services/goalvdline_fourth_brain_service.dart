import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'diego_ai_service.dart';
import 'goalvdline_third_brain_service.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';
import 'smartbet_market_ease_index_service.dart';

/// B67: a *dependent ensemble*, not a fourth independent AI model.
/// None of these diagnostics are betting instructions or calibrated odds.
enum GoalVdLineFourthBrainStatus {
  insufficientSources,
  exploratoryShadow,
  historicalShadow,
  divergentShadow,
}

class GoalVdLineFourthBrainForecast {
  final String market;
  final double probability;
  final double smartBetProbability;
  final double diegoProbability;
  final double? simulatorProbability;
  final String? simulatorInputSource;

  /// Combined weights sum to 1; the simulator uses its parent's budget.
  final double smartBetWeight;
  final double diegoWeight;
  final double simulatorWeight;
  final double disagreementPoints;
  final bool evidenceQualified;
  final GoalVdLineFourthBrainStatus status;

  const GoalVdLineFourthBrainForecast({
    required this.market,
    required this.probability,
    required this.smartBetProbability,
    required this.diegoProbability,
    required this.simulatorProbability,
    required this.simulatorInputSource,
    required this.smartBetWeight,
    required this.diegoWeight,
    required this.simulatorWeight,
    required this.disagreementPoints,
    required this.evidenceQualified,
    required this.status,
  });

  /// The fourth brain NEVER authorizes a live coupon.
  bool get allowedForLiveSelection => false;
}

class GoalVdLineFourthBrainReport {
  final int fixtureId;
  final DateTime evaluatedAt;
  final List<GoalVdLineFourthBrainForecast> forecasts;

  const GoalVdLineFourthBrainReport({
    required this.fixtureId,
    required this.evaluatedAt,
    required this.forecasts,
  });
}

/// Pure market-by-market synthesis. Requires both independently sourced
/// SmartBet and Diego forecasts for precisely the SAME full-time market.
/// Simulator is a dependent sensitivity estimate, never a third vote.
class GoalVdLineFourthBrainService {
  const GoalVdLineFourthBrainService();

  static const markets = <String>[
    '1', 'X', '2', 'GOAL', 'NO GOAL', 'OVER 2.5', 'UNDER 2.5',
  ];

  static const double _simulatorFractionOfParent = 0.25;
  static const double _divergenceThreshold = 0.20;
  static const String modelVersion = 'META_B67_V1';

  static bool _valid(double? p) =>
      p != null && p.isFinite && p >= 0 && p <= 1;

  static bool _fullDistribution(List<double> numbers) =>
      numbers.every(_valid) &&
      numbers.reduce((a, b) => a + b) >= 0.98 &&
      numbers.reduce((a, b) => a + b) <= 1.02;

  /// No value is manufactured when a data family is absent or contradictory.
  static Map<String, double> smartBetMarkets(AnalysisResult analysis) {
    if (analysis.smartScore <= 0) return const {};
    final result = <String, double>{};
    final triple = [
      analysis.homeProbability / 100.0,
      analysis.drawProbability / 100.0,
      analysis.awayProbability / 100.0,
    ];
    if (_fullDistribution(triple)) {
      result.addAll({'1': triple[0], 'X': triple[1], '2': triple[2]});
    }
    final goal = [analysis.goalProbability / 100.0,
      analysis.noGoalProbability / 100.0];
    if (_fullDistribution(goal)) {
      result.addAll({'GOAL': goal[0], 'NO GOAL': goal[1]});
    }
    final totals = [analysis.over25Probability / 100.0,
      analysis.under25Probability / 100.0];
    if (_fullDistribution(totals)) {
      result.addAll({'OVER 2.5': totals[0], 'UNDER 2.5': totals[1]});
    }
    return result;
  }

  static Map<String, double> diegoMarkets(DiegoAiAnalysis analysis) {
    final result = <String, double>{};
    final triple = [analysis.homeProbability, analysis.drawProbability,
      analysis.awayProbability];
    if (_fullDistribution(triple)) {
      result.addAll({'1': triple[0], 'X': triple[1], '2': triple[2]});
    }
    final goal = [analysis.goalProbability, analysis.noGoalProbability];
    if (_fullDistribution(goal)) {
      result.addAll({'GOAL': goal[0], 'NO GOAL': goal[1]});
    }
    final totals = [analysis.over25Probability, analysis.under25Probability];
    if (_fullDistribution(totals)) {
      result.addAll({'OVER 2.5': totals[0], 'UNDER 2.5': totals[1]});
    }
    return result;
  }

  static Map<String, double> simulatorMarkets(GoalVdLineThirdBrainReport? report) {
    if (report == null) return const {};
    final result = <String, double>{};
    for (final market in markets) {
      final probability = report.forMarket(market)?.probability;
      if (_valid(probability)) result[market] = probability!;
    }
    return result;
  }

  GoalVdLineFourthBrainReport evaluate({
    required int fixtureId,
    required String country,
    required String league,
    required DateTime kickoffAt,
    required DateTime asOf,
    required Map<String, double> smartBet,
    required Map<String, double> diego,
    Map<String, double> simulator = const {},
    String? simulatorInputSource,
    Iterable<SmartBetAnalysisRecord> historicalRecords =
        const <SmartBetAnalysisRecord>[],
  }) {
    final clock = asOf.toUtc();
    final kickoff = kickoffAt.toUtc();
    if (fixtureId <= 0 || !clock.isBefore(kickoff) ||
        country.trim().isEmpty || league.trim().isEmpty) {
      return GoalVdLineFourthBrainReport(
        fixtureId: fixtureId, evaluatedAt: clock, forecasts: const [],
      );
    }

    // evaluate() enforces the "known before clock" cut-off on resolved
    // fixtures. No current/future match outcome can modify these weights.
    // Additional defense: reject settlement labels inconsistent with the
    // recorded full-time score before allowing them into historic weights.
    final history = historicalRecords.where((record) {
      final home = record.actualHomeGoals, away = record.actualAwayGoals;
      if (home == null || away == null || home < 0 || away < 0) return false;
      final settled = SmartBetAnalysisMarketSettlement.evaluate(
        market: record.market, homeGoals: home, awayGoals: away,
      );
      return (record.status == SmartBetAnalysisStatus.correct &&
              settled == SmartBetAnalysisSettlement.correct) ||
          (record.status == SmartBetAnalysisStatus.wrong &&
              settled == SmartBetAnalysisSettlement.wrong);
    }).toList(growable: false);
    final evidence = history.isEmpty ? null
        : const SmartBetMarketEaseIndexService().evaluate(
            records: history, asOf: clock);

    final results = <GoalVdLineFourthBrainForecast>[];
    for (final market in markets) {
      final smartP = smartBet[market], diegoP = diego[market];
      if (!_valid(smartP) || !_valid(diegoP)) continue;

      // Independent parent weights use the conservative B66 MEI only if
      // BOTH engines have sufficient historical data for the same segment.
      double smartParentWeight = 0.5;
      var qualified = false;
      if (evidence != null) {
        double? scoreFor(SmartBetAnalysisEngine engine) {
          for (final entry in evidence.entries) {
            final segment = entry.evidence;
            if (segment.engine == engine &&
                segment.country.trim() == country.trim() &&
                segment.league.trim() == league.trim() &&
                segment.market == market &&
                entry.availableForShadowComparison) {
              return entry.score;
            }
          }
          return null;
        }

        final a = scoreFor(SmartBetAnalysisEngine.smartBet);
        final b = scoreFor(SmartBetAnalysisEngine.diego);
        if (a != null && b != null) {
          qualified = true;
          // Limit the effect of historical advantage: even large differences
          // cannot turn one model into an unchallenged authority.
          smartParentWeight = (0.5 + 0.0025 * (a - b))
              .clamp(0.4, 0.6).toDouble();
        }
      }

      final diegoParentWeight = 1.0 - smartParentWeight;
      final parent = simulatorInputSource;
      final simP = simulator[market];
      final hasSimulator = _valid(simP) &&
          (parent == 'smartBet' || parent == 'diego');

      final double simulatorWeight;
      final double smartWeight;
      final double diegoWeight;
      if (hasSimulator && parent == 'smartBet') {
        simulatorWeight = smartParentWeight * _simulatorFractionOfParent;
        smartWeight = smartParentWeight - simulatorWeight;
        diegoWeight = diegoParentWeight;
      } else if (hasSimulator && parent == 'diego') {
        simulatorWeight = diegoParentWeight * _simulatorFractionOfParent;
        smartWeight = smartParentWeight;
        diegoWeight = diegoParentWeight - simulatorWeight;
      } else {
        simulatorWeight = 0;
        smartWeight = smartParentWeight;
        diegoWeight = diegoParentWeight;
      }

      final p = (smartP! * smartWeight +
          diegoP! * diegoWeight +
          (hasSimulator ? simP! * simulatorWeight : 0))
          .clamp(0.0, 1.0).toDouble();
      final gap = (smartP - diegoP).abs();
      final status = gap >= _divergenceThreshold
          ? GoalVdLineFourthBrainStatus.divergentShadow
          : qualified
              ? GoalVdLineFourthBrainStatus.historicalShadow
              : GoalVdLineFourthBrainStatus.exploratoryShadow;

      results.add(GoalVdLineFourthBrainForecast(
        market: market,
        probability: p,
        smartBetProbability: smartP,
        diegoProbability: diegoP,
        simulatorProbability: hasSimulator ? simP : null,
        simulatorInputSource: hasSimulator ? parent : null,
        smartBetWeight: smartWeight,
        diegoWeight: diegoWeight,
        simulatorWeight: simulatorWeight,
        disagreementPoints: gap * 100,
        evidenceQualified: qualified,
        status: status,
      ));
    }

    results.sort((a, b) {
      final byP = b.probability.compareTo(a.probability);
      return byP != 0 ? byP : a.market.compareTo(b.market);
    });
    return GoalVdLineFourthBrainReport(
      fixtureId: fixtureId,
      evaluatedAt: clock,
      forecasts: List.unmodifiable(results),
    );
  }

  /// Convenience adapter: no odds, no bookmaker, no future results.
  GoalVdLineFourthBrainReport evaluateEngines({
    required MatchModel match,
    required AnalysisResult smartBet,
    required DiegoAiAnalysis? diego,
    required DateTime asOf,
    Iterable<SmartBetAnalysisRecord> historicalRecords =
        const <SmartBetAnalysisRecord>[],
  }) {
    if (diego == null || diego.match.fixtureId != match.fixtureId) {
      return GoalVdLineFourthBrainReport(
        fixtureId: match.fixtureId, evaluatedAt: asOf.toUtc(), forecasts: const [],
      );
    }
    final kickoff = DateTime.tryParse(match.date);
    if (kickoff == null) {
      return GoalVdLineFourthBrainReport(
        fixtureId: match.fixtureId, evaluatedAt: asOf.toUtc(), forecasts: const [],
      );
    }
    final sim = const GoalVdLineThirdBrainService()
        .evaluate(smartBet: smartBet, diego: diego);
    return evaluate(
      fixtureId: match.fixtureId,
      country: match.country,
      league: match.league,
      kickoffAt: kickoff,
      asOf: asOf,
      smartBet: smartBetMarkets(smartBet),
      diego: diegoMarkets(diego),
      simulator: simulatorMarkets(sim),
      // Explicitly preserve dependence: xG from SmartBet or Diego.
      simulatorInputSource: sim == null ? null :
          sim.sharesDiegoInputs ? 'diego' : 'smartBet',
      historicalRecords: historicalRecords,
    );
  }

  /// Used for immutable pre-kickoff local history; never uploads to Neon
  /// and never modifies coupons or sportsbook odds.
  Future<List<SmartBetAnalysisRecord>> capture({
    required SmartBetAnalysisHistoryStore store,
    required MatchModel match,
    required AnalysisResult smartBet,
    required DiegoAiAnalysis? diego,
    required SmartBetAnalysisSource source,
    DateTime? recordedAt,
  }) async {
    final now = (recordedAt ?? DateTime.now()).toUtc();
    final report = evaluateEngines(
      match: match, smartBet: smartBet, diego: diego,
      asOf: now, historicalRecords: store.records,
    );
    if (report.forecasts.isEmpty) return const [];

    final byMarket = <String, double>{
      for (final f in report.forecasts) f.market: f.probability,
    };
    // Simulation origin is stable across the whole fixture.
    final simOrigin = report.forecasts
        .firstWhere((f) => f.simulatorInputSource != null,
            orElse: () => report.forecasts.first)
        .simulatorInputSource;
    final classification = '${modelVersion}_SHADOW_'
        '${simOrigin == 'smartBet' ? 'SMARTBET_XG' :
            simOrigin == 'diego' ? 'DIEGO_XG' : 'NO_SIM'}';
    return store.registerMarketBundle(
      engine: SmartBetAnalysisEngine.metaAi,
      source: source,
      fixtureId: match.fixtureId,
      homeTeam: match.homeTeam,
      awayTeam: match.awayTeam,
      league: match.league,
      country: match.country,
      matchDate: DateTime.parse(match.date).toUtc(),
      markets: byMarket,
      classification: classification,
      recordedAt: now,
    );
  }
}
