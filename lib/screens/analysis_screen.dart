import 'package:flutter/material.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import 'analysis_detail_screen.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late Future<List<MatchModel>> _matches;

  final Set<String> _expandedCountries = {};
  final Set<String> _expandedLeagues = {};

  String _searchText = "";

  @override
  void initState() {
    super.initState();
    _matches = MatchRepository.getTodayMatches();
  }

  // ============================================================
  // BANDIERE
  // ============================================================

  String _countryFlag(String country) {
    const flags = <String, String>{
      "Italia": "🇮🇹",
      "Inghilterra": "🏴",
      "Spagna": "🇪🇸",
      "Germania": "🇩🇪",
      "Francia": "🇫🇷",
      "Olanda": "🇳🇱",
      "Paesi Bassi": "🇳🇱",
      "Portogallo": "🇵🇹",
      "Belgio": "🇧🇪",
      "Turchia": "🇹🇷",
      "USA": "🇺🇸",
      "United States": "🇺🇸",
      "Brasile": "🇧🇷",
      "Argentina": "🇦🇷",
      "Messico": "🇲🇽",
      "Giappone": "🇯🇵",
      "Corea del Sud": "🇰🇷",
      "Australia": "🇦🇺",
      "Canada": "🇨🇦",
      "Grecia": "🇬🇷",
      "Svizzera": "🇨🇭",
      "Austria": "🇦🇹",
      "Danimarca": "🇩🇰",
      "Svezia": "🇸🇪",
      "Norvegia": "🇳🇴",
      "Finlandia": "🇫🇮",
      "Polonia": "🇵🇱",
      "Croazia": "🇭🇷",
      "Serbia": "🇷🇸",
      "Romania": "🇷🇴",
      "Ucraina": "🇺🇦",
      "Scozia": "🏴",
      "Irlanda": "🇮🇪",
      "Irlanda del Nord": "🇬🇧",
      "Repubblica Ceca": "🇨🇿",
      "Slovacchia": "🇸🇰",
      "Ungheria": "🇭🇺",
      "Slovenia": "🇸🇮",
      "Bulgaria": "🇧🇬",
      "Israele": "🇮🇱",
      "Arabia Saudita": "🇸🇦",
      "Emirati Arabi Uniti": "🇦🇪",
      "Qatar": "🇶🇦",
      "Cina": "🇨🇳",
      "India": "🇮🇳",
      "Sudafrica": "🇿🇦",
      "Colombia": "🇨🇴",
      "Cile": "🇨🇱",
      "Perù": "🇵🇪",
      "Ecuador": "🇪🇨",
      "Uruguay": "🇺🇾",
      "Paraguay": "🇵🇾",
      "Bolivia": "🇧🇴",
      "Costa Rica": "🇨🇷",
    };

    return flags[country] ?? "🌍";
  }

  // ============================================================
  // DATA
  // ============================================================

  String _formatDate(String date) {
    if (date.isEmpty) {
      return "";
    }

    try {
      final parsed = DateTime.parse(date).toLocal();

      final day = parsed.day.toString().padLeft(2, '0');
      final month = parsed.month.toString().padLeft(2, '0');
      final hour = parsed.hour.toString().padLeft(2, '0');
      final minute = parsed.minute.toString().padLeft(2, '0');

      return "$day/$month $hour:$minute";
    } catch (_) {
      return date;
    }
  }

  // ============================================================
  // RICERCA
  // ============================================================

  bool _matchesSearch(MatchModel match) {
    if (_searchText.trim().isEmpty) {
      return true;
    }

    final search = _searchText.toLowerCase().trim();

    return match.homeTeam.toLowerCase().contains(search) ||
        match.awayTeam.toLowerCase().contains(search) ||
        match.league.toLowerCase().contains(search) ||
        match.country.toLowerCase().contains(search);
  }

  // ============================================================
  // RAGGRUPPA PER NAZIONE
  // ============================================================

  Map<String, List<MatchModel>> _groupByCountry(List<MatchModel> matches) {
    final grouped = <String, List<MatchModel>>{};

    for (final match in matches) {
      if (!_matchesSearch(match)) {
        continue;
      }

      final country = match.country.trim().isEmpty
          ? "Altri"
          : match.country.trim();

      grouped.putIfAbsent(country, () => []);
      grouped[country]!.add(match);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Map.fromEntries(entries);
  }

  // ============================================================
  // RAGGRUPPA PER CAMPIONATO
  // ============================================================

  Map<String, List<MatchModel>> _groupByLeague(List<MatchModel> matches) {
    final grouped = <String, List<MatchModel>>{};

    for (final match in matches) {
      final league = match.league.trim().isEmpty
          ? "Competizione"
          : match.league.trim();

      grouped.putIfAbsent(league, () => []);
      grouped[league]!.add(match);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Map.fromEntries(entries);
  }

  // ============================================================
  // COLORE SMART SCORE
  // ============================================================

  Color _scoreColor(int score) {
    if (score >= 80) {
      return Colors.green;
    }

    if (score >= 65) {
      return Colors.orange;
    }

    return Colors.redAccent;
  }

  // ============================================================
  // BOX PROBABILITÀ
  // ============================================================

  Widget _probabilityBox(String label, int probability) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            "$probability%",
            style: const TextStyle(
              color: Color(0xFF00C853),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CARD PARTITA
  // ============================================================

  Widget _matchCard(BuildContext context, MatchModel match) {
    return FutureBuilder<AnalysisResult>(
      future: SmartCore.analyze(match),
      builder: (context, snapshot) {
        // --------------------------------------------------------
        // CARICAMENTO
        // --------------------------------------------------------

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            margin: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
            color: const Color(0xFF1F2937),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.homeTeam,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    match.awayTeam,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        "Analisi AI in corso...",
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        // --------------------------------------------------------
        // ERRORE
        // --------------------------------------------------------

        if (snapshot.hasError) {
          return Card(
            margin: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
            color: const Color(0xFF1F2937),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${match.homeTeam} - ${match.awayTeam}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Errore durante l'analisi",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final result = snapshot.data!;
        final scoreColor = _scoreColor(result.smartScore);

        // --------------------------------------------------------
        // CARD
        // --------------------------------------------------------

        return Card(
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
          color: const Color(0xFF1F2937),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // COMPETIZIONE + ORARIO
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.league,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      _formatDate(match.date),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // SQUADRE
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.homeTeam,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        "VS",
                        style: TextStyle(
                          color: Colors.white30,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        match.awayTeam,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 13),

                // SMART SCORE
                Row(
                  children: [
                    Icon(Icons.psychology, color: scoreColor, size: 22),
                    const SizedBox(width: 7),
                    Text(
                      "Smart Score ${result.smartScore}",
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      result.prediction,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // PROGRESS
                LinearProgressIndicator(
                  value: result.smartScore.clamp(0, 100) / 100,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(20),
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                ),

                const SizedBox(height: 12),

                // PROBABILITÀ
                Row(
                  children: [
                    Expanded(
                      child: _probabilityBox("1", result.homeProbability),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _probabilityBox("X", result.drawProbability),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _probabilityBox("2", result.awayProbability),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // RISCHIO / VALUE
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        "Rischio: ${result.risk}",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Icon(Icons.show_chart, color: Colors.amber, size: 17),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        "Value: ${result.valueBet}",
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 13),

                // ANALIZZA
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnalysisDetailScreen(
                            match: match,
                            result: result,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.psychology, size: 18),
                    label: const Text(
                      "ANALIZZA PARTITA",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // SEZIONE CAMPIONATO
  // ============================================================

  Widget _leagueSection(
    BuildContext context,
    String country,
    String league,
    List<MatchModel> matches,
  ) {
    final key = "$country::$league";
    final expanded = _expandedLeagues.contains(key);

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedLeagues.remove(key);
              } else {
                _expandedLeagues.add(key);
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF172033),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    league,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${matches.length}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...matches.map((match) => _matchCard(context, match)),
      ],
    );
  }

  // ============================================================
  // SEZIONE NAZIONE
  // ============================================================

  Widget _countrySection(
    BuildContext context,
    String country,
    List<MatchModel> matches,
  ) {
    final expanded = _expandedCountries.contains(country);
    final leagues = _groupByLeague(matches);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedCountries.remove(country);
              } else {
                _expandedCountries.add(country);
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: expanded
                    ? const Color(0xFF00C853).withValues(alpha: 0.5)
                    : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                Text(
                  _countryFlag(country),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        country,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${matches.length} partite",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: expanded ? const Color(0xFF00C853) : Colors.white54,
                ),
              ],
            ),
          ),
        ),

        if (expanded)
          ...leagues.entries.map(
            (entry) => _leagueSection(context, country, entry.key, entry.value),
          ),

        const SizedBox(height: 4),
      ],
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "SMARTBET AI",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            "Analisi intelligente delle partite",
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 14),

          // RICERCA
          TextField(
            onChanged: (value) {
              setState(() {
                _searchText = value;
              });
            },
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Cerca squadra o campionato...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              suffixIcon: _searchText.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: () {
                        setState(() {
                          _searchText = "";
                        });
                      },
                    ),
              filled: true,
              fillColor: const Color(0xFF1F2937),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        title: const Text(
          "Analisi Partite",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF111827),
      ),
      body: FutureBuilder<List<MatchModel>>(
        future: _matches,
        builder: (context, snapshot) {
          // ------------------------------------------------------
          // LOADING
          // ------------------------------------------------------

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ------------------------------------------------------
          // ERRORE
          // ------------------------------------------------------

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }

          // ------------------------------------------------------
          // NESSUNA PARTITA
          // ------------------------------------------------------

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Column(
              children: [
                _header(),
                const Expanded(
                  child: Center(
                    child: Text(
                      "Nessuna partita disponibile",
                      style: TextStyle(color: Colors.white70, fontSize: 17),
                    ),
                  ),
                ),
              ],
            );
          }

          final allMatches = snapshot.data!;
          final grouped = _groupByCountry(allMatches);

          // ------------------------------------------------------
          // NESSUN RISULTATO DI RICERCA
          // ------------------------------------------------------

          if (grouped.isEmpty) {
            return Column(
              children: [
                _header(),
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            color: Colors.white38,
                            size: 55,
                          ),
                          SizedBox(height: 12),
                          Text(
                            "Nessuna partita trovata",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              _header(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 30),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final entry = grouped.entries.elementAt(index);

                    return _countrySection(context, entry.key, entry.value);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
