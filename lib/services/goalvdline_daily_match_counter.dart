import '../models/match_model.dart';
import 'italy_schedule_filter.dart';

/// Counts distinct, not-yet-started fixtures for TODAY in the local timezone.
/// It does NOT claim an AI forecast or a >=65% playable pick exists.
class GoalVdLineDailyMatchCounter {
  const GoalVdLineDailyMatchCounter._();

  /// Tutte le fixture non iniziate del giorno fornite dal provider, senza
  /// filtro campionati; non sono pronostici verificati o quotati.
  static int countAllForToday(
    Iterable<MatchModel> matches, {
    required DateTime now,
  }) => _count(matches, now: now, italyScheduleOnly: false);

  /// Le sole fixture compatibili con il filtro "Palinsesto Italia".
  static int countForToday(
    Iterable<MatchModel> matches, {
    required DateTime now,
  }) => _count(matches, now: now, italyScheduleOnly: true);

  static int _count(
    Iterable<MatchModel> matches, {
    required DateTime now,
    required bool italyScheduleOnly,
  }) {
    final clock = now.toLocal();
    final seen = <int>{};
    for (final match in matches) {
      if (match.fixtureId <= 0 ||
          !match.hasTeamIds ||
          (italyScheduleOnly && !ItalyScheduleFilter.allows(match))) {
        continue;
      }

      final status = match.statusShort.trim().toUpperCase();
      if (status.isNotEmpty && status != 'NS') continue;

      final parsed = DateTime.tryParse(match.date);
      if (parsed == null) continue;
      final kickoff = parsed.toLocal();
      if (!kickoff.isAfter(clock) ||
          kickoff.year != clock.year ||
          kickoff.month != clock.month ||
          kickoff.day != clock.day) {
        continue;
      }
      seen.add(match.fixtureId);
    }
    return seen.length;
  }
}
