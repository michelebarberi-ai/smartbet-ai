import '../models/match_model.dart';
import '../widgets/competition_filter_sheet.dart';
import 'italy_schedule_filter.dart';

/// B74: filter the calendar before any SmartCore or advanced AI work.
///
/// A selected bookmaker-compatible Italian schedule is a competition-coverage
/// filter, not proof that the individual event/market is listed by a .it
/// bookmaker. Real quoted markets are still checked after sporting analysis.
class GoalVdLineCombinationsFixturePolicy {
  const GoalVdLineCombinationsFixturePolicy._();

  static List<MatchModel> eligibleMatches(
    Iterable<MatchModel> matches, {
    required bool italianScheduleOnly,
    required Set<String> selectedCompetitionKeys,
    required bool Function(MatchModel) isUpcoming,
  }) {
    return matches.where((match) {
      if (match.fixtureId <= 0 || !match.hasTeamIds || !isUpcoming(match)) {
        return false;
      }
      if (italianScheduleOnly && !ItalyScheduleFilter.allows(match)) {
        return false;
      }
      if (selectedCompetitionKeys.isEmpty) return true;
      return selectedCompetitionKeys.contains('id:${match.leagueId}') ||
          selectedCompetitionKeys.contains(CompetitionFilterSheet.keyFor(match));
    }).toList(growable: false);
  }
}
