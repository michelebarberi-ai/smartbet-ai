import 'dart:math' as math;

import '../models/match_model.dart';
import 'team_form_service.dart';

/// Input costruito autonomamente dal terzo cervello sui risultati grezzi FT.
/// Non riutilizza xG, probabilita' o SmartScore di SmartBet/Diego.
/// La fonte delle fixture rimane condivisa (API-Football via cache).
class GoalVdLineThirdBrainOwnInput {
  final double expectedHomeGoals;
  final double expectedAwayGoals;
  final int dataConfidence;
  final int homeVenueMatches;
  final int awayVenueMatches;
  final String source;
  final String modelVersion;

  const GoalVdLineThirdBrainOwnInput({
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
    required this.dataConfidence,
    required this.homeVenueMatches,
    required this.awayVenueMatches,
    required this.source,
    required this.modelVersion,
  });
}

/// Questa fase non accende altre API: usa esclusivamente i risultati
/// grezzi gia' ottenuti nel normale percorso SmartCore.
class GoalVdLineThirdBrainOwnInputService {
  const GoalVdLineThirdBrainOwnInputService();

  static const String modelVersion = 'third-brain-venue-scorelines-v1';
  static const String inputSource = 'Risultati FT API-Football · modello autonomo';
  static const int minimumVenueMatches = 3;
  static const int maximumHistoricalDays = 365;

  GoalVdLineThirdBrainOwnInput? fromCachedFixtureHistory({
    required MatchModel match,
    required DateTime observedAt,
  }) {
    if (!match.hasTeamIds) return null;
    final home = TeamFormService.cachedRecentFixtures(
      teamId: match.homeTeamId, last: 10,
    );
    final away = TeamFormService.cachedRecentFixtures(
      teamId: match.awayTeamId, last: 10,
    );
    if (home == null || away == null) return null;
    return fromFixtureHistory(
      match: match,
      observedAt: observedAt,
      homeHistory: home,
      awayHistory: away,
    );
  }

  GoalVdLineThirdBrainOwnInput? fromFixtureHistory({
    required MatchModel match,
    required DateTime observedAt,
    required List<dynamic> homeHistory,
    required List<dynamic> awayHistory,
  }) {
    final kickoff = DateTime.tryParse(match.date)?.toUtc();
    final cutoff = observedAt.toUtc();
    if (kickoff == null || !cutoff.isBefore(kickoff) ||
        !match.hasTeamIds) return null;

    final homeVenue = _extract(
      homeHistory, teamId: match.homeTeamId, homeVenue: true,
      cutoff: cutoff, targetFixtureId: match.fixtureId,
    );
    final awayVenue = _extract(
      awayHistory, teamId: match.awayTeamId, homeVenue: false,
      cutoff: cutoff, targetFixtureId: match.fixtureId,
    );
    if (homeVenue.length < minimumVenueMatches ||
        awayVenue.length < minimumVenueMatches) return null;

    // Semplice modello alternativo di gol segnati/subiti nel contesto
    // CASA/TRASFERTA, con shrinkage verso 1.25 e senza quote.
    // Non e' ancora calibrato su un campione prospettico.
    double average(Iterable<int> values) =>
        values.reduce((a, b) => a + b) / values.length;
    final homeScored = average(homeVenue.map((g) => g.scored));
    final homeAllowed = average(homeVenue.map((g) => g.conceded));
    final awayScored = average(awayVenue.map((g) => g.scored));
    final awayAllowed = average(awayVenue.map((g) => g.conceded));

    final effectiveN = math.min(homeVenue.length, awayVenue.length);
    // Il ridimensionamento evita estremi statistici con 3 sole gare.
    final weight = effectiveN / (effectiveN + 5.0);
    double estimate(double forRate, double againstRate) {
      final smoothed = (math.sqrt(forRate * againstRate) * weight) +
          (1.25 * (1.0 - weight));
      return smoothed.clamp(0.1, 4.5).toDouble();
    }

    return GoalVdLineThirdBrainOwnInput(
      expectedHomeGoals: estimate(homeScored, awayAllowed),
      expectedAwayGoals: estimate(awayScored, homeAllowed),
      // Indice di copertura campione, NON probabilita' di successo.
      dataConfidence: (40 + 4 * effectiveN).clamp(0, 80),
      homeVenueMatches: homeVenue.length,
      awayVenueMatches: awayVenue.length,
      source: inputSource,
      modelVersion: modelVersion,
    );
  }

  List<_VenueResult> _extract(
    List<dynamic> raw, {
    required int teamId,
    required bool homeVenue,
    required DateTime cutoff,
    required int targetFixtureId,
  }) {
    final unique = <int, _VenueResult>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final fixture = item['fixture'];
      final teams = item['teams'];
      final goals = item['goals'];
      if (fixture is! Map || teams is! Map || goals is! Map) continue;
      final id = _integer(fixture['id']);
      final date = DateTime.tryParse(fixture['date']?.toString() ?? '')?.toUtc();
      final status = fixture['status'];
      if (id == null || id <= 0 || id == targetFixtureId ||
          date == null || !date.isBefore(cutoff) ||
          cutoff.difference(date) > const Duration(days: maximumHistoricalDays) ||
          status is! Map || status['short']?.toString().toUpperCase() != 'FT') {
        continue;
      }
      final h = teams['home'];
      final a = teams['away'];
      if (h is! Map || a is! Map) continue;
      final homeId = _integer(h['id']);
      final awayId = _integer(a['id']);
      final isValid = homeVenue ? homeId == teamId : awayId == teamId;
      if (!isValid) continue;
      final homeGoals = _integer(goals['home']);
      final awayGoals = _integer(goals['away']);
      if (homeGoals == null || awayGoals == null ||
          homeGoals < 0 || awayGoals < 0 || homeGoals > 20 ||
          awayGoals > 20) continue;
      unique.putIfAbsent(id, () => _VenueResult(
        scored: homeVenue ? homeGoals : awayGoals,
        conceded: homeVenue ? awayGoals : homeGoals,
      ));
    }
    return unique.values.toList(growable: false);
  }

  int? _integer(dynamic value) => value is int ? value : null;
}

class _VenueResult {
  final int scored;
  final int conceded;
  const _VenueResult({required this.scored, required this.conceded});
}
