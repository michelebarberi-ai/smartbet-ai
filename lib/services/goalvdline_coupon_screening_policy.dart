import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'italy_schedule_filter.dart';

/// B70: weekend dates and a data-quality-aware preselection.
/// No odds or bookmaker information enters this ranking.
class GoalVdLineCouponScreeningPolicy {
  const GoalVdLineCouponScreeningPolicy._();

  /// The next Saturday/Sunday pair. On Saturday include today;
  /// on Sunday take the following weekend (not yesterday).
  static List<DateTime> nextWeekend(DateTime current) {
    final today = DateTime(current.year, current.month, current.day);
    final daysUntilSaturday =
        (DateTime.saturday - today.weekday + 7) % 7;
    final saturday = today.add(Duration(days: daysUntilSaturday));
    return [saturday, saturday.add(const Duration(days: 1))];
  }

  /// Apply user-selected Italian schedule coverage BEFORE the advanced
  /// quota-independent shortlist, not after it has been exhausted.
  static List<MatchModel> eligibleMatches(
    List<MatchModel> matches, {
    required bool italianScheduleOnly,
  }) => italianScheduleOnly
      ? matches.where(ItalyScheduleFilter.allows).toList()
      : List<MatchModel>.of(matches);

  /// Preselection should not be driven by broad OR markets (1X OR U3.5,
  /// 1X OR O1.5), trivially safe lines (U5.5), or a quoted line.
  /// These markets remain available for the subsequent full analysis.
  static int comparableMarketProbability(AnalysisResult result) {
    final p = <int>[
      result.homeProbability,
      result.drawProbability,
      result.awayProbability,
      (result.homeProbability + result.drawProbability).clamp(0, 100),
      (result.drawProbability + result.awayProbability).clamp(0, 100),
      (result.homeProbability + result.awayProbability).clamp(0, 100),
      result.over15Probability,
      result.under15Probability,
      result.over25Probability,
      result.under25Probability,
      result.goalProbability,
      result.noGoalProbability,
    ];
    var best = 0;
    for (final candidate in p) {
      if (candidate > best) best = candidate;
    }
    return best;
  }

  /// Score only for selecting fixtures worthy of expensive advanced AI.
  /// The probability of the chosen final market is computed later and is
  /// never changed by competition weights or bookmaker information.
  static double screeningScore({
    required AnalysisResult analysis,
    required MatchModel match,
  }) {
    final p = comparableMarketProbability(analysis).toDouble();
    final smart = analysis.smartScore.clamp(0, 100).toDouble();
    final completeness = analysis.dataConfidence.clamp(0, 100).toDouble();
    final competitionWeight = match.aiWeight.clamp(0.0, 1.0) * 100;
    return p * 0.40 +
        smart * 0.42 +
        completeness * 0.12 +
        competitionWeight * 0.06;
  }

  /// Prevent one league from monopolizing the 36 advanced slots just
  /// because its OR/low lines are close to 100%. A second pass fills all
  /// remaining places from the original sporting ranking.
  static List<T> diversifiedTop<T>(
    List<T> ranked, {
    required int limit,
    required int Function(T) leagueIdOf,
    required String Function(T) leagueNameOf,
    required String Function(T) countryOf,
    int initialMaxPerLeague = 4,
  }) {
    if (limit <= 0) return <T>[];
    final picked = <T>[];
    final selected = <int>{};
    final perLeague = <String, int>{};

    String leagueKey(T item) {
      final id = leagueIdOf(item);
      if (id > 0) return 'id:$id';
      return '${countryOf(item).trim().toLowerCase()}|'
          '${leagueNameOf(item).trim().toLowerCase()}';
    }

    for (var i = 0; i < ranked.length && picked.length < limit; i++) {
      final key = leagueKey(ranked[i]);
      if ((perLeague[key] ?? 0) >= initialMaxPerLeague) continue;
      picked.add(ranked[i]);
      selected.add(i);
      perLeague[key] = (perLeague[key] ?? 0) + 1;
    }

    for (var i = 0; i < ranked.length && picked.length < limit; i++) {
      if (selected.contains(i)) continue;
      picked.add(ranked[i]);
    }
    return picked;
  }
}
