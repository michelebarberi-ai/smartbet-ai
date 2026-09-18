import 'package:flutter/material.dart';

import '../models/match_model.dart';

class CompetitionFilterSheet {
  const CompetitionFilterSheet._();

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
      final country = match.country.trim().isEmpty
          ? 'Altro'
          : match.country.trim();
      final league = match.league.trim().isEmpty
          ? 'Competizione'
          : match.league.trim();
      byCountry.putIfAbsent(country, () => <String, String>{})[keyFor(match)] =
          league;
    }

    final countries = byCountry.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final allKeys = <String>{
      for (final leagues in byCountry.values) ...leagues.keys,
    };
    if (allKeys.isEmpty) return null;

    final initial = selectedKeys.isEmpty
        ? <String>{...allKeys}
        : <String>{...selectedKeys.where(allKeys.contains)};

    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      builder: (context) {
        var selected = initial;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allSelected = selected.length == allKeys.length;
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
                          Icon(Icons.public, color: Color(0xFF00C853)),
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
                    CheckboxListTile(
                      value: allSelected,
                      activeColor: const Color(0xFF00C853),
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
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        children: [
                          for (final country in countries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 14, 8, 5),
                              child: Text(
                                country.toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF00C853),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                            for (final entry
                                in (byCountry[country]!.entries.toList()..sort(
                                  (a, b) => a.value.toLowerCase().compareTo(
                                    b.value.toLowerCase(),
                                  ),
                                )))
                              CheckboxListTile(
                                dense: true,
                                value: selected.contains(entry.key),
                                activeColor: const Color(0xFF00C853),
                                title: Text(
                                  entry.value,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
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
                              ),
                          ],
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
                            backgroundColor: const Color(0xFF00C853),
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
