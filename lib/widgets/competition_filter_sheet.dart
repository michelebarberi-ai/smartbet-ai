import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/match_model.dart';
import '../services/football_competition_catalog_service.dart';
import '../services/goalvdline_competition_order.dart';

/// Selettore comune: le selezioni restano specifiche della singola schermata,
/// mentre i campionati preferiti sono condivisi e persistenti sul dispositivo.
class CompetitionFilterSheet {
  const CompetitionFilterSheet._();

  static const String _favoritesStorageKey =
      'goalvdline.favorite_competition_keys.v1';
  static const Color _accent = Color(0xFF00C853);

  static String keyFor(MatchModel match) =>
      keyForNames(match.country, match.league);

  static String keyForNames(String country, String league) {
    final area = country.trim().isEmpty ? 'Altro' : country.trim();
    final name = league.trim().isEmpty ? 'Competizione' : league.trim();
    return '$area|||$name';
  }

  static String _favoriteKey(String key) {
    final separator = key.indexOf('|||');
    if (separator < 0) return key;
    final country = GoalVdLineCompetitionOrder.country(key.substring(0, separator));
    final league = key.substring(separator + 3).trim().toLowerCase();
    return '$country|||$league';
  }

  static Future<Set<String>?> show({
    required BuildContext context,
    required List<MatchModel> matches,
    required Set<String> selectedKeys,
    List<FootballCompetitionCatalogEntry> catalog = const [],
  }) {
    final catalogIds = catalog.map((e) => e.id).toSet();
    final counts = <String, int>{};
    for (final m in matches) {
      final key = catalogIds.contains(m.leagueId)
          ? 'id:${m.leagueId}'
          : keyFor(m);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return showLeagues(
      context: context,
      leagues: matches
          .where((m) => !catalogIds.contains(m.leagueId))
          .map((m) => (m.country, m.league)),
      catalog: catalog,
      availabilityCounts: counts,
      selectedKeys: selectedKeys,
    );
  }

  static Future<Set<String>?> showLeagues({
    required BuildContext context,
    required Iterable<(String, String)> leagues,
    required Set<String> selectedKeys,
    Iterable<FootballCompetitionCatalogEntry> catalog = const [],
    Map<String, int> availabilityCounts = const {},
  }) async {
    final byCountry = <String, Map<String, String>>{};
    final catalogFavoriteKeys = <String, String>{};
    for (final item in catalog) {
      final country = GoalVdLineCompetitionOrder.displayCountry(
          item.country, item.name);
      byCountry.putIfAbsent(country, () => {})[item.selectionKey] = item.name;
      catalogFavoriteKeys[item.selectionKey] =
          '${GoalVdLineCompetitionOrder.country(item.country)}|||'
          '${item.name.trim().toLowerCase()}';
    }
    String favoriteKeyFor(String key) =>
        catalogFavoriteKeys[key] ?? _favoriteKey(key);
    for (final (area, name) in leagues) {
      final country = GoalVdLineCompetitionOrder.displayCountry(area, name);
      final league = name.trim().isEmpty ? 'Competizione' : name.trim();
      byCountry.putIfAbsent(country, () => {})[keyForNames(area, name)] = league;
    }
    final countries = byCountry.keys.toList()
      ..sort(GoalVdLineCompetitionOrder.compareCountries);
    final allKeys = <String>{
      for (final leagues in byCountry.values) ...leagues.keys,
    };
    if (allKeys.isEmpty) return null;

    final preferenceStore = await SharedPreferences.getInstance();
    final favorites = <String>{
      ...(preferenceStore.getStringList(_favoritesStorageKey) ?? <String>[]).map(_favoriteKey),
    };
    if (!context.mounted) return null;

    final initial = selectedKeys.isEmpty
        ? <String>{...allKeys}
        : <String>{...selectedKeys.where(allKeys.contains)};

    var selected = initial;
    var favoriteKeys = favorites;
    var search = '';
    var saving = false;
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      builder: (context) {

        return StatefulBuilder(
          builder: (context, setModalState) {
            final allSelected = selected.length == allKeys.length;
            // Conteggi delle fixture realmente presenti nel periodo richiesto:
            // non includono le competizioni del solo catalogo stagionale.
            // Sono candidate all'analisi, non pronostici già validati.
            final totalFixtures = availabilityCounts.values.fold<int>(
              0, (sum, count) => sum + count,
            );
            final selectedFixtures = selected.fold<int>(
              0, (sum, key) => sum + (availabilityCounts[key] ?? 0),
            );
            final favoriteAvailable = allKeys.where((key) => favoriteKeys.contains(favoriteKeyFor(key))).toSet();
            final matchingCountries = <String, Map<String, String>>{};
            for (final country in countries) {
              final filtered = <String, String>{};
              for (final entry in byCountry[country]!.entries) {
                if (search.isEmpty ||
                    country.toLowerCase().contains(search) ||
                    entry.value.toLowerCase().contains(search)) {
                  filtered[entry.key] = entry.value;
                }
              }
              if (filtered.isNotEmpty) matchingCountries[country] = filtered;
            }

            final visibleItems = <Object>[];
            if (favoriteAvailable.isNotEmpty && search.isEmpty) {
              visibleItems.add('★ CAMPIONATI PREFERITI');
              for (final country in countries) {
                visibleItems.addAll(byCountry[country]!.entries.where(
                  (entry) => favoriteAvailable.contains(entry.key)));
              }
            }
            for (final group in matchingCountries.entries) {
              visibleItems.add(group.key.toUpperCase());
              visibleItems.addAll(group.value.entries.toList()
                ..sort((a, b) => GoalVdLineCompetitionOrder.compareLeagues(
                    a.value, b.value)));
            }
            if (visibleItems.isEmpty) visibleItems.add('__none__');

            Widget leagueRow(MapEntry<String, String> entry) {
              final key = favoriteKeyFor(entry.key);
              final starred = favoriteKeys.contains(key);
              return CheckboxListTile(
                dense: true,
                value: selected.contains(entry.key),
                activeColor: _accent,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.value,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      key: ValueKey('competition-match-count-${entry.key}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${availabilityCounts[entry.key] ?? 0} partite',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: availabilityCounts.containsKey(entry.key)
                    ? Text(
                        '${availabilityCounts[entry.key]} partite future nel periodo',
                        style: const TextStyle(
                          color: Colors.greenAccent, fontSize: 10),
                      )
                    : const Text('Nessuna partita futura nel periodo selezionato',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                secondary: IconButton(
                  tooltip: starred
                      ? 'Rimuovi dai preferiti'
                      : 'Aggiungi ai preferiti',
                  icon: Icon(
                    starred ? Icons.star : Icons.star_border,
                    color: starred ? Colors.amberAccent : Colors.white38,
                  ),
                  onPressed: saving ? null : () async {
                    final nextFavorites = <String>{...favoriteKeys};
                    if (!nextFavorites.add(key)) {
                      nextFavorites.remove(key);
                    }
                    setModalState(() => saving = true);
                    try {
                      final saved = await preferenceStore.setStringList(
                        _favoritesStorageKey, nextFavorites.toList()..sort(),
                      );
                      if (!saved) throw StateError('Preferiti non salvati');
                      if (context.mounted) {
                        setModalState(() => favoriteKeys = nextFavorites);
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(content: Text('Impossibile salvare i preferiti.')),
                        );
                      }
                    } finally {
                      if (context.mounted) setModalState(() => saving = false);
                    }
                  },
                ),
                onChanged: (value) {
                  setModalState(() {
                    final next = <String>{...selected};
                    if (value == true) {
                      next.add(entry.key);
                    } else {
                      next.remove(entry.key);
                    }
                    selected = next;
                  });
                },
              );
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.82,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Row(
                        children: [
                          Icon(Icons.public, color: _accent),
                          SizedBox(width: 10),
                          Text(
                            'Scegli campionati',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TextField(
                        onChanged: (value) => setModalState(
                          () => search = value.trim().toLowerCase(),
                        ),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Cerca un campionato o una nazione',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white54,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1F2937),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      value: allSelected,
                      activeColor: _accent,
                      title: const Text(
                        'Tutte le competizioni del catalogo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${allKeys.length} nel catalogo · '
                        '${availabilityCounts.values.where((n) => n > 0).length} '
                        'con partite future nel periodo',
                        style: const TextStyle(color: Colors.white38),
                      ),
                      onChanged: (value) {
                        setModalState(() {
                          selected = value == true
                              ? <String>{...allKeys}
                              : <String>{};
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star,
                            color: Colors.amberAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Preferiti (${favoriteAvailable.length})',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: favoriteAvailable.isEmpty
                                ? null
                                : () => setModalState(
                                    () => selected = <String>{
                                      ...favoriteAvailable,
                                    },
                                  ),
                            child: const Text('SOLO PREFERITI'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: visibleItems.length,
                        itemBuilder: (context, index) {
                          final item = visibleItems[index];
                          if (item is MapEntry<String, String>) {
                            return leagueRow(item);
                          }
                          if (item == '__none__') {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Nessun campionato trovato.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54)),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 14, 8, 5),
                            child: Text(item.toString(),
                              style: const TextStyle(
                                color: _accent, fontSize: 12,
                                fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PARTITE SELEZIONATE: $selectedFixtures / $totalFixtures',
                            key: const Key('competition-selected-fixtures-total'),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Partite future candidate all’analisi: la disponibilità '
                            'di statistiche, quote e mercati va verificata.',
                            style: TextStyle(
                              color: Colors.white54, fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(
                                  context,
                                  selected.length == allKeys.length
                                      ? <String>{}
                                      : selected,
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(
                            selected.isEmpty
                                ? 'SELEZIONA ALMENO UN CAMPIONATO'
                                : 'APPLICA (${selected.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The current screen owns its selection. All screens open the same favorites.
class CompetitionFilterButton extends StatelessWidget {
  final Iterable<(String, String)> leagues;
  final Set<String> selectedKeys;
  final ValueChanged<Set<String>> onChanged;

  const CompetitionFilterButton({
    super.key, required this.leagues, required this.selectedKeys, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.filter_list),
      label: Text(selectedKeys.isEmpty ? 'Campionati' : 'Campionati (${selectedKeys.length})'),
      onPressed: () async {
        final result = await CompetitionFilterSheet.showLeagues(
          context: context, leagues: leagues, selectedKeys: selectedKeys,
        );
        if (context.mounted && result != null) onChanged(result);
      },
    );
  }
}
