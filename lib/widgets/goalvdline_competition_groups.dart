import 'package:flutter/material.dart';

import '../services/goalvdline_competition_order.dart';

/// P22: presentazione gerarchica riutilizzabile e senza chiamate di rete.
/// Riceve gli elementi GIA' selezionati dall'algoritmo, non li filtra.
class GoalVdLineCompetitionGroups<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T) countryOf;
  final String Function(T) leagueOf;
  final String? Function(T)? dateOf;
  final Widget Function(BuildContext, T) itemBuilder;
  final String namespace;

  const GoalVdLineCompetitionGroups({
    super.key,
    required this.items,
    required this.countryOf,
    required this.leagueOf,
    this.dateOf,
    required this.itemBuilder,
    required this.namespace,
  });

  @override
  Widget build(BuildContext context) {
    // Stable sorting: ties preserve original AI/feed order.
    final ordered = items.asMap().entries.toList()
      ..sort((a, b) {
        final country = GoalVdLineCompetitionOrder.compareCountries(
          GoalVdLineCompetitionOrder.displayCountry(
            countryOf(a.value),
            leagueOf(a.value),
          ),
          GoalVdLineCompetitionOrder.displayCountry(
            countryOf(b.value),
            leagueOf(b.value),
          ),
        );
        if (country != 0) return country;
        final league = GoalVdLineCompetitionOrder.compareLeagues(
          leagueOf(a.value),
          leagueOf(b.value),
        );
        if (league != 0) return league;
        final date = GoalVdLineCompetitionOrder.compareTimes(
          dateOf?.call(a.value),
          dateOf?.call(b.value),
        );
        return date == 0 ? a.key.compareTo(b.key) : date;
      });

    final grouped = <String, Map<String, List<T>>>{};
    for (final entry in ordered) {
      final item = entry.value;
      final country = GoalVdLineCompetitionOrder.displayCountry(
        countryOf(item),
        leagueOf(item),
      );
      final league = GoalVdLineCompetitionOrder.league(leagueOf(item));
      grouped
          .putIfAbsent(country, () => <String, List<T>>{})
          .putIfAbsent(league, () => <T>[])
          .add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final countryEntry in grouped.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ExpansionTile(
                key: PageStorageKey<String>(
                  'p22:$namespace:${countryEntry.key}',
                ),
                initiallyExpanded: true,
                backgroundColor: const Color(0xFF162235),
                collapsedBackgroundColor: const Color(0xFF1F2937),
                iconColor: const Color(0xFF00C853),
                collapsedIconColor: Colors.white60,
                textColor: Colors.white,
                collapsedTextColor: Colors.white,
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(
                  '${GoalVdLineCompetitionOrder.flag(countryEntry.key)} '
                  '${countryEntry.key}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${countryEntry.value.values.fold<int>(0, (sum, rows) => sum + rows.length)} partite',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                children: [
                  for (final leagueEntry in countryEntry.value.entries)
                    ExpansionTile(
                      key: PageStorageKey<String>(
                        'p22:$namespace:${countryEntry.key}:${leagueEntry.key}',
                      ),
                      initiallyExpanded: true,
                      iconColor: const Color(0xFF00C853),
                      collapsedIconColor: Colors.white54,
                      backgroundColor: const Color(0xFF111827),
                      collapsedBackgroundColor: const Color(0xFF111827),
                      tilePadding: const EdgeInsets.only(left: 18, right: 14),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              leagueEntry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          Text(
                            '${leagueEntry.value.length}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      children: [
                        for (final item in leagueEntry.value)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(11, 0, 11, 1),
                            child: itemBuilder(context, item),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
