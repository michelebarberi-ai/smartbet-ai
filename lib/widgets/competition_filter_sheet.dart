import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/match_model.dart';
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
  }) => showLeagues(
    context: context,
    leagues: matches.map((m) => (m.country, m.league)),
    selectedKeys: selectedKeys,
  );

  static Future<Set<String>?> showLeagues({
    required BuildContext context,
    required Iterable<(String, String)> leagues,
    required Set<String> selectedKeys,
  }) async {
    final byCountry = <String, Map<String, String>>{};
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
            final favoriteAvailable = allKeys.where((key) => favoriteKeys.contains(_favoriteKey(key))).toSet();
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

            Widget leagueRow(MapEntry<String, String> entry) {
              final key = _favoriteKey(entry.key);
              final starred = favoriteKeys.contains(key);
              return CheckboxListTile(
                dense: true,
                value: selected.contains(entry.key),
                activeColor: _accent,
                title: Text(
                  entry.value,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
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
                        'Tutti i campionati',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${allKeys.length} disponibili',
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
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        children: [
                          if (favoriteAvailable.isNotEmpty && search.isEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(8, 14, 8, 5),
                              child: Text(
                                '★ CAMPIONATI PREFERITI',
                                style: TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            for (final country in countries)
                              for (final entry
                                  in (byCountry[country]!.entries.where(
                                    (entry) => favoriteAvailable.contains(entry.key),
                                  ).toList()..sort((a, b) => GoalVdLineCompetitionOrder.compareLeagues(a.value, b.value))))
                                leagueRow(entry),
                            const Divider(color: Colors.white12),
                          ],
                          for (final countryEntry in matchingCountries.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 14, 8, 5),
                              child: Text(
                                countryEntry.key.toUpperCase(),
                                style: const TextStyle(
                                  color: _accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                            for (final entry in (countryEntry.value.entries
                                .toList()
                              ..sort(
                                (a, b) => a.value
                                    .toLowerCase()
                                    .compareTo(b.value.toLowerCase()),
                              )))
                              leagueRow(entry),
                          ],
                          if (matchingCountries.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nessun campionato trovato.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
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
