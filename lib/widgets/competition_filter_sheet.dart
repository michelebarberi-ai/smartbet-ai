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

  static String keyFor(MatchModel match) {
    final country = match.country.trim().isEmpty
        ? 'Altro'
        : match.country.trim();
    final league = match.league.trim().isEmpty
        ? 'Competizione'
        : match.league.trim();
    return '$country|||$league';
  }

  static Future<Set<String>?> show({
    required BuildContext context,
    required List<MatchModel> matches,
    required Set<String> selectedKeys,
  }) async {
    final byCountry = <String, Map<String, String>>{};

    for (final match in matches) {
      // La classificazione resta puramente visiva. L'identificativo dei
      // campionati non cambia, per rispettare filtri e preferiti precedenti.
      final country = GoalVdLineCompetitionOrder.displayCountry(
        match.country,
        match.league,
      );
      final league = match.league.trim().isEmpty
          ? 'Competizione'
          : match.league.trim();
      byCountry.putIfAbsent(country, () => <String, String>{})[keyFor(match)] =
          league;
    }

    final countries = byCountry.keys.toList()
      ..sort(GoalVdLineCompetitionOrder.compareCountries);
    final allKeys = <String>{
      for (final leagues in byCountry.values) ...leagues.keys,
    };
    if (allKeys.isEmpty) return null;

    final preferenceStore = await SharedPreferences.getInstance();
    final favorites = <String>{
      ...?preferenceStore.getStringList(_favoritesStorageKey),
    };
    if (!context.mounted) return null;

    final initial = selectedKeys.isEmpty
        ? <String>{...allKeys}
        : <String>{...selectedKeys.where(allKeys.contains)};

    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      builder: (context) {
        var selected = initial;
        var favoriteKeys = favorites;
        var search = '';

        return StatefulBuilder(
          builder: (context, setModalState) {
            final allSelected = selected.length == allKeys.length;
            final favoriteAvailable = allKeys.intersection(favoriteKeys);
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
              final starred = favoriteKeys.contains(entry.key);
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
                  onPressed: () async {
                    final nextFavorites = <String>{...favoriteKeys};
                    if (!nextFavorites.add(entry.key)) {
                      nextFavorites.remove(entry.key);
                    }
                    setModalState(() => favoriteKeys = nextFavorites);
                    final persisted = nextFavorites.toList()..sort();
                    final saved = await preferenceStore.setStringList(
                      _favoritesStorageKey,
                      persisted,
                    );
                    if (!saved && context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('Impossibile salvare i preferiti.'),
                        ),
                      );
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
                                  in byCountry[country]!.entries.where(
                                    (entry) =>
                                        favoriteAvailable.contains(entry.key),
                                  ))
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
