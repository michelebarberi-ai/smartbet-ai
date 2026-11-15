/// B57 — external opinion consensus, a separate evidence layer.
///
/// The observations MUST come from publisher-approved feeds or direct voluntary
/// submissions. Telegram's Bot Platform terms prohibit bulk scraping of
/// public channels for AI datasets; this service does no network scraping.
///
/// Consensus is agreement among tracked, independent sources, NOT a
/// probability that the outcome will occur.
class GoalVdLineExternalOpinion {
  final String sourceId;
  final int fixtureId;
  final DateTime kickoffAt;
  final DateTime publishedAt;
  final DateTime firstObservedAt;
  final String marketFamily;
  final String outcome;
  final String sourceReference;

  const GoalVdLineExternalOpinion({
    required this.sourceId,
    required this.fixtureId,
    required this.kickoffAt,
    required this.publishedAt,
    required this.firstObservedAt,
    required this.marketFamily,
    required this.outcome,
    required this.sourceReference,
  });
}

class GoalVdLineWebConsensus {
  final int fixtureId;
  final String marketFamily;
  final int independentSources;
  final String? majorityOutcome;
  final int majoritySources;
  final int conflictingSources;
  final bool sufficientCoverage;

  const GoalVdLineWebConsensus({
    required this.fixtureId,
    required this.marketFamily,
    required this.independentSources,
    required this.majorityOutcome,
    required this.majoritySources,
    required this.conflictingSources,
    required this.sufficientCoverage,
  });

  /// Agreement between sources, not calibrated chance of a winning bet.
  double? get agreementPercent =>
      !sufficientCoverage || independentSources == 0
          ? null
          : 100.0 * majoritySources / independentSources;
}

class GoalVdLineExternalConsensusService {
  const GoalVdLineExternalConsensusService();

  /// Number of *independent* publishers, not channel messages.
  static const int minimumIndependentSources = 3;

  List<GoalVdLineWebConsensus> aggregate({
    required Iterable<GoalVdLineExternalOpinion> observations,
    required DateTime asOf,
    required Set<String> authorizedSourceIds,
  }) {
    final cutoff = asOf.toUtc();
    final accepted = <String, GoalVdLineExternalOpinion>{};
    final conflicts = <String>{};
    final byFixture = <String, Set<String>>{};

    for (final raw in observations) {
      final id = raw.sourceId.trim();
      final family = raw.marketFamily.trim().toUpperCase();
      final outcome = raw.outcome.trim().toUpperCase();
      final kickoff = raw.kickoffAt.toUtc();
      final publish = raw.publishedAt.toUtc();
      final observed = raw.firstObservedAt.toUtc();
      if (raw.fixtureId <= 0 ||
          !authorizedSourceIds.contains(id) ||
          raw.sourceReference.trim().isEmpty ||
          family.isEmpty ||
          outcome.isEmpty ||
          !publish.isBefore(kickoff) ||
          !observed.isBefore(kickoff) ||
          publish.isAfter(observed) ||
          observed.isAfter(cutoff)) {
        continue;
      }
      final unique = '$id|${raw.fixtureId}|$family';
      final bucket = '${raw.fixtureId}|$family';
      byFixture.putIfAbsent(bucket, () => {}).add(unique);
      if (conflicts.contains(unique)) continue;
      final prior = accepted[unique];
      if (prior == null) {
        accepted[unique] = raw;
      } else if (prior.outcome.trim().toUpperCase() != outcome ||
          prior.kickoffAt.toUtc() != kickoff) {
        // A source posting incompatible outcomes for the same market-family
        // must not contribute its most convenient version post hoc.
        conflicts.add(unique);
        accepted.remove(unique);
      }
    }

    final results = <GoalVdLineWebConsensus>[];
    for (final group in byFixture.entries) {
      final votes = <String, int>{};
      var conflictsInGroup = 0;
      for (final unique in group.value) {
        if (conflicts.contains(unique)) {
          conflictsInGroup++;
          continue;
        }
        final observation = accepted[unique];
        if (observation == null) continue;
        final outcome = observation.outcome.trim().toUpperCase();
        votes[outcome] = (votes[outcome] ?? 0) + 1;
      }
      if (votes.isEmpty && conflictsInGroup == 0) continue;
      final ranked = votes.entries.toList()
        ..sort((a, b) {
          final count = b.value.compareTo(a.value);
          return count != 0 ? count : a.key.compareTo(b.key);
        });
      final independent = votes.values.fold<int>(0, (a, b) => a + b);
      final majority = ranked.isEmpty ? null : ranked.first;
      final enough = independent >= minimumIndependentSources;
      final parts = group.key.split('|');
      results.add(GoalVdLineWebConsensus(
        fixtureId: int.parse(parts.first),
        marketFamily: parts.sublist(1).join('|'),
        independentSources: independent,
        majorityOutcome: enough ? majority?.key : null,
        majoritySources: enough ? (majority?.value ?? 0) : 0,
        conflictingSources: conflictsInGroup,
        sufficientCoverage: enough,
      ));
    }
    results.sort((a, b) {
      final fixture = a.fixtureId.compareTo(b.fixtureId);
      return fixture != 0 ? fixture :
          a.marketFamily.compareTo(b.marketFamily);
    });
    return List.unmodifiable(results);
  }
}
