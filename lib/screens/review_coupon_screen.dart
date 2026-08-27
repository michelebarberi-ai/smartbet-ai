import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';

class ReviewCouponScreen extends StatefulWidget {
  const ReviewCouponScreen({super.key});

  @override
  State<ReviewCouponScreen> createState() => _ReviewCouponScreenState();
}

class _ReviewDecision {
  final String action;
  final String selectedMarket;
  final int selectedProbability;
  final String suggestedMarket;
  final int suggestedProbability;
  final int smartScore;
  final String reason;

  const _ReviewDecision({
    required this.action,
    required this.selectedMarket,
    required this.selectedProbability,
    required this.suggestedMarket,
    required this.suggestedProbability,
    required this.smartScore,
    required this.reason,
  });
}

class _AnalyzedSelection {
  final _ReviewSelection selection;
  final AnalysisResult analysis;
  final int selectedProbability;
  final String suggestedMarket;
  final int suggestedProbability;
  final double reliability;

  const _AnalyzedSelection({
    required this.selection,
    required this.analysis,
    required this.selectedProbability,
    required this.suggestedMarket,
    required this.suggestedProbability,
    required this.reliability,
  });
}

class _ReviewSelection {
  final MatchModel match;
  String market;

  _ReviewSelection({required this.match, required this.market});
}

class _ReviewCouponScreenState extends State<ReviewCouponScreen> {
  static const int _maximumSelections = 12;
  static const String _storageKey = 'review_coupon_selections_v1';

  static const List<String> _markets = [
    '1',
    'X',
    '2',
    '1X',
    'X2',
    '12',
    'OVER 1.5',
    'UNDER 1.5',
    'OVER 2.5',
    'UNDER 2.5',
    'GOAL',
    'NO GOAL',
  ];

  final List<_ReviewSelection> _selections = [];

  bool _loadingMatches = false;
  bool _loadingSaved = true;

  bool _analyzing = false;
  int _analysisProcessed = 0;
  int _targetKeepCount = 0;

  final Map<int, _ReviewDecision> _reviewResults = {};

  @override
  void initState() {
    super.initState();
    _loadSelections();
  }

  int _probabilityFor(AnalysisResult result, String market) {
    switch (market) {
      case '1':
        return result.homeProbability;
      case 'X':
        return result.drawProbability;
      case '2':
        return result.awayProbability;
      case '1X':
        return (result.homeProbability + result.drawProbability).clamp(0, 100);
      case 'X2':
        return (result.drawProbability + result.awayProbability).clamp(0, 100);
      case '12':
        return (result.homeProbability + result.awayProbability).clamp(0, 100);
      case 'OVER 1.5':
        return result.over15Probability;
      case 'UNDER 1.5':
        return result.under15Probability;
      case 'OVER 2.5':
        return result.over25Probability;
      case 'UNDER 2.5':
        return result.under25Probability;
      case 'GOAL':
        return result.goalProbability;
      case 'NO GOAL':
        return result.noGoalProbability;
      default:
        return 0;
    }
  }

  List<String> _alternativesFor(String selectedMarket) {
    if (const ['1', 'X', '2', '1X', 'X2', '12'].contains(selectedMarket)) {
      return const ['1', 'X', '2', '1X', 'X2', '12'];
    }

    return const [
      'OVER 1.5',
      'UNDER 1.5',
      'OVER 2.5',
      'UNDER 2.5',
      'GOAL',
      'NO GOAL',
    ];
  }

  ({String market, int probability}) _bestAlternative(
    AnalysisResult result,
    String selectedMarket,
  ) {
    var bestMarket = selectedMarket;
    var bestProbability = _probabilityFor(result, selectedMarket);

    for (final market in _alternativesFor(selectedMarket)) {
      final probability = _probabilityFor(result, market);

      if (probability > bestProbability) {
        bestMarket = market;
        bestProbability = probability;
      }
    }

    return (market: bestMarket, probability: bestProbability);
  }

  Future<void> _analyzeCoupon() async {
    if (_analyzing || _selections.length < 2) {
      return;
    }

    final target =
        (_targetKeepCount <= 0 ? _selections.length : _targetKeepCount).clamp(
          2,
          _selections.length,
        );

    setState(() {
      _analyzing = true;
      _analysisProcessed = 0;
      _reviewResults.clear();
    });

    try {
      final analyzed = <_AnalyzedSelection>[];

      for (final selection in _selections) {
        try {
          final analysis = await SmartCore.analyze(selection.match);

          final selectedProbability = _probabilityFor(
            analysis,
            selection.market,
          );

          final alternative = _bestAlternative(analysis, selection.market);

          final reliability =
              (selectedProbability * 0.70) + (analysis.smartScore * 0.30);

          analyzed.add(
            _AnalyzedSelection(
              selection: selection,
              analysis: analysis,
              selectedProbability: selectedProbability,
              suggestedMarket: alternative.market,
              suggestedProbability: alternative.probability,
              reliability: reliability,
            ),
          );
        } catch (_) {
          analyzed.add(
            _AnalyzedSelection(
              selection: selection,
              analysis: const AnalysisResult(
                smartScore: 0,
                homeProbability: 0,
                drawProbability: 0,
                awayProbability: 0,
                prediction: 'N/D',
                valueBet: 'N/D',
                risk: 'Dati insufficienti',
                explanation: '',
              ),
              selectedProbability: 0,
              suggestedMarket: selection.market,
              suggestedProbability: 0,
              reliability: 0,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _analysisProcessed++;
          });
        }
      }

      analyzed.sort((a, b) => b.reliability.compareTo(a.reliability));

      final keepFixtures = analyzed
          .take(target)
          .map((item) => item.selection.match.fixtureId)
          .toSet();

      final decisions = <int, _ReviewDecision>{};

      for (final item in analyzed) {
        final fixtureId = item.selection.match.fixtureId;
        final selectedMarket = item.selection.market;

        if (!keepFixtures.contains(fixtureId)) {
          decisions[fixtureId] = _ReviewDecision(
            action: 'SCARTA',
            selectedMarket: selectedMarket,
            selectedProbability: item.selectedProbability,
            suggestedMarket: item.suggestedMarket,
            suggestedProbability: item.suggestedProbability,
            smartScore: item.analysis.smartScore,
            reason:
                'È tra le selezioni meno affidabili rispetto alle altre della schedina.',
          );
          continue;
        }

        final improvement =
            item.suggestedProbability - item.selectedProbability;

        final shouldModify =
            item.suggestedMarket != selectedMarket &&
            improvement >= 12 &&
            item.suggestedProbability >= 55;

        if (shouldModify) {
          decisions[fixtureId] = _ReviewDecision(
            action: 'MODIFICA',
            selectedMarket: selectedMarket,
            selectedProbability: item.selectedProbability,
            suggestedMarket: item.suggestedMarket,
            suggestedProbability: item.suggestedProbability,
            smartScore: item.analysis.smartScore,
            reason:
                'Esiste un mercato statisticamente più solido per questa partita.',
          );
        } else {
          decisions[fixtureId] = _ReviewDecision(
            action: 'TIENI',
            selectedMarket: selectedMarket,
            selectedProbability: item.selectedProbability,
            suggestedMarket: selectedMarket,
            suggestedProbability: item.selectedProbability,
            smartScore: item.analysis.smartScore,
            reason:
                'La tua selezione è coerente con l’analisi e rientra tra quelle da mantenere.',
          );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _reviewResults
          ..clear()
          ..addAll(decisions);
      });
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
        });
      }
    }
  }

  Future<void> _applyAiSuggestions() async {
    if (_reviewResults.isEmpty) {
      return;
    }

    final modifications = _reviewResults.values
        .where((item) => item.action == 'MODIFICA')
        .length;

    final discards = _reviewResults.values
        .where((item) => item.action == 'SCARTA')
        .length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Applicare i suggerimenti AI?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'SmartBet modificherà $modifications selezioni '
            'e rimuoverà $discards partite.\n\n'
            'Le selezioni indicate come TIENI resteranno invariate.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ANNULLA'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('APPLICA'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() {
      for (final selection in _selections) {
        final decision = _reviewResults[selection.match.fixtureId];

        if (decision == null) {
          continue;
        }

        if (decision.action == 'MODIFICA') {
          selection.market = decision.suggestedMarket;
        }
      }

      _selections.removeWhere((selection) {
        final decision = _reviewResults[selection.match.fixtureId];

        return decision?.action == 'SCARTA';
      });

      _reviewResults.clear();

      if (_targetKeepCount > _selections.length) {
        _targetKeepCount = _selections.length;
      }

      if (_selections.length >= 2 && _targetKeepCount < 2) {
        _targetKeepCount = _selections.length;
      }
    });

    await _saveSelections();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Suggerimenti AI applicati alla schedina.')),
    );
  }

  Color _decisionColor(String action) {
    switch (action) {
      case 'TIENI':
        return const Color(0xFF00C853);
      case 'MODIFICA':
        return Colors.orangeAccent;
      case 'SCARTA':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  Widget _decisionBox(_ReviewDecision decision) {
    final color = _decisionColor(decision.action);

    return Container(
      margin: const EdgeInsets.only(top: 13),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                decision.action == 'TIENI'
                    ? Icons.check_circle_outline
                    : decision.action == 'MODIFICA'
                    ? Icons.swap_horiz
                    : Icons.cancel_outlined,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                decision.action,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                'Smart Score ${decision.smartScore}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Tua scelta: ${decision.selectedMarket} '
            '• ${decision.selectedProbability}%',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (decision.action == 'MODIFICA') ...[
            const SizedBox(height: 5),
            Text(
              'Suggerimento AI: '
              '${decision.suggestedMarket} '
              '• ${decision.suggestedProbability}%',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            decision.reason,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  bool _isUpcoming(MatchModel match) {
    try {
      return DateTime.parse(match.date).toLocal().isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _formatDate(String raw) {
    try {
      final date = DateTime.parse(raw).toLocal();

      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic> _matchToJson(MatchModel match) {
    return {
      'fixtureId': match.fixtureId,
      'homeTeamId': match.homeTeamId,
      'awayTeamId': match.awayTeamId,
      'homeTeam': match.homeTeam,
      'awayTeam': match.awayTeam,
      'league': match.league,
      'leagueId': match.leagueId,
      'country': match.country,
      'countryCode': match.countryCode,
      'date': match.date,
      'leagueType': match.leagueType,
      'isEuropeanCup': match.isEuropeanCup,
      'isFriendly': match.isFriendly,
      'isNational': match.isNational,
      'aiWeight': match.aiWeight,
      'smartScore': match.smartScore,
      'homeWin': match.homeWin,
      'draw': match.draw,
      'awayWin': match.awayWin,
      'valueBet': match.valueBet,
      'odd': match.odd,
    };
  }

  MatchModel _matchFromJson(Map<String, dynamic> json) {
    return MatchModel(
      fixtureId: json['fixtureId'] ?? 0,
      homeTeamId: json['homeTeamId'] ?? 0,
      awayTeamId: json['awayTeamId'] ?? 0,
      homeTeam: json['homeTeam'] ?? '',
      awayTeam: json['awayTeam'] ?? '',
      league: json['league'] ?? '',
      leagueId: json['leagueId'] ?? 0,
      country: json['country'] ?? '',
      countryCode: json['countryCode'] ?? '',
      date: json['date'] ?? '',
      leagueType: json['leagueType'] ?? 'domestic',
      isEuropeanCup: json['isEuropeanCup'] ?? false,
      isFriendly: json['isFriendly'] ?? false,
      isNational: json['isNational'] ?? false,
      aiWeight: (json['aiWeight'] ?? 0.70).toDouble(),
      smartScore: json['smartScore'] ?? 0,
      homeWin: json['homeWin'] ?? 0,
      draw: json['draw'] ?? 0,
      awayWin: json['awayWin'] ?? 0,
      valueBet: json['valueBet'] ?? '',
      odd: (json['odd'] ?? 0).toDouble(),
    );
  }

  Future<void> _loadSelections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);

      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return;
      }

      final restored = <_ReviewSelection>[];

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final map = Map<String, dynamic>.from(item);

        final matchData = map['match'];

        if (matchData is! Map) {
          continue;
        }

        final match = _matchFromJson(Map<String, dynamic>.from(matchData));

        if (!_isUpcoming(match)) {
          continue;
        }

        final market = map['market']?.toString() ?? '1';

        restored.add(
          _ReviewSelection(
            match: match,
            market: _markets.contains(market) ? market : '1',
          ),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selections
          ..clear()
          ..addAll(restored.take(_maximumSelections));
      });

      await _saveSelections();
    } catch (_) {
      // Se il salvataggio locale fosse corrotto, la schermata
      // continua semplicemente senza schedina salvata.
    } finally {
      if (mounted) {
        setState(() {
          _loadingSaved = false;
        });
      }
    }
  }

  Future<void> _saveSelections() async {
    final prefs = await SharedPreferences.getInstance();

    final data = _selections
        .map(
          (item) => {'match': _matchToJson(item.match), 'market': item.market},
        )
        .toList();

    await prefs.setString(_storageKey, jsonEncode(data));
  }

  Future<void> _addMatch() async {
    if (_selections.length >= _maximumSelections) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Puoi inserire al massimo 12 partite.')),
      );
      return;
    }

    setState(() {
      _loadingMatches = true;
    });

    try {
      final all = await MatchRepository.getTodayMatches();

      final alreadySelected = _selections
          .map((item) => item.match.fixtureId)
          .toSet();

      final matches = all
          .where(
            (match) =>
                match.hasTeamIds &&
                _isUpcoming(match) &&
                !alreadySelected.contains(match.fixtureId),
          )
          .toList();

      matches.sort((a, b) {
        try {
          return DateTime.parse(a.date).compareTo(DateTime.parse(b.date));
        } catch (_) {
          return 0;
        }
      });

      if (!mounted) {
        return;
      }

      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Non ci sono altre partite disponibili da aggiungere.',
            ),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<MatchModel>(
        context: context,
        backgroundColor: const Color(0xFF111827),
        isScrollControlled: true,
        builder: (context) {
          var searchText = '';

          return StatefulBuilder(
            builder: (context, setSheetState) {
              final normalizedSearch = searchText.trim().toLowerCase();

              final filteredMatches = normalizedSearch.isEmpty
                  ? matches
                  : matches.where((match) {
                      final haystack =
                          '${match.homeTeam} '
                                  '${match.awayTeam} '
                                  '${match.league} '
                                  '${match.country}'
                              .toLowerCase();

                      return haystack.contains(normalizedSearch);
                    }).toList();

              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
                        child: Row(
                          children: [
                            Icon(Icons.sports_soccer, color: Color(0xFF00C853)),
                            SizedBox(width: 10),
                            Text(
                              'Scegli una partita',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                        child: TextField(
                          autofocus: true,
                          onChanged: (value) {
                            setSheetState(() {
                              searchText = value;
                            });
                          },
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Cerca squadra, campionato o paese...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Color(0xFF00C853),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF1F2937),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white12),
                      Expanded(
                        child: filteredMatches.isEmpty
                            ? const Center(
                                child: Text(
                                  'Nessuna partita trovata',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredMatches.length,
                                separatorBuilder: (_, __) => const Divider(
                                  color: Colors.white10,
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final match = filteredMatches[index];

                                  return ListTile(
                                    title: Text(
                                      '${match.homeTeam} - ${match.awayTeam}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${match.country} • ${match.league} • '
                                      '${_formatDate(match.date)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.add_circle_outline,
                                      color: Color(0xFF00C853),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context, match);
                                    },
                                  );
                                },
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

      if (selected == null || !mounted) {
        return;
      }

      setState(() {
        _selections.add(_ReviewSelection(match: selected, market: '1'));
      });

      await _saveSelections();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile caricare le partite. Riprova tra poco.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingMatches = false;
        });
      }
    }
  }

  Future<void> _removeSelection(int index) async {
    setState(() {
      _selections.removeAt(index);
    });

    await _saveSelections();
  }

  Future<void> _clearSelections() async {
    if (_selections.isEmpty) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Svuotare la schedina?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Tutte le selezioni inserite verranno eliminate.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ANNULLA'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('SVUOTA'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() {
      _selections.clear();
    });

    await _saveSelections();
  }

  Widget _selectionCard(_ReviewSelection item, int index) {
    final match = item.match;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${match.homeTeam} - ${match.awayTeam}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${match.league} • ${_formatDate(match.date)}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _removeSelection(index),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'TUO PRONOSTICO',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 7),
          DropdownButtonFormField<String>(
            value: item.market,
            dropdownColor: const Color(0xFF1F2937),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF111827),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            iconEnabledColor: const Color(0xFF00C853),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            items: _markets
                .map(
                  (market) => DropdownMenuItem<String>(
                    value: market,
                    child: Text(market),
                  ),
                )
                .toList(),
            onChanged: (value) async {
              if (value == null) {
                return;
              }

              setState(() {
                item.market = value;
                _reviewResults.clear();
              });

              await _saveSelections();
            },
          ),

          if (_reviewResults[match.fixtureId] != null)
            _decisionBox(_reviewResults[match.fixtureId]!),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAnalyze = _selections.length >= 2;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Revisione Schedina AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selections.isNotEmpty)
            IconButton(
              tooltip: 'Svuota schedina',
              onPressed: _clearSelections,
              icon: const Icon(
                Icons.delete_sweep_outlined,
                color: Colors.redAccent,
              ),
            ),
        ],
      ),
      body: _loadingSaved
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      color: Color(0xFF00C853),
                      size: 30,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Fai controllare la tua schedina',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Inserisci fino a 12 partite e indica il pronostico '
                  'che hai scelto per ciascuna.',
                  style: TextStyle(color: Colors.white60, height: 1.45),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      '${_selections.length}/$_maximumSelections selezioni',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed:
                          _loadingMatches ||
                              _selections.length >= _maximumSelections
                          ? null
                          : _addMatch,
                      icon: _loadingMatches
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: const Text(
                        'AGGIUNGI',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_selections.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          color: Color(0xFF00C853),
                          size: 42,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Nessuna partita inserita',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Premi AGGIUNGI per iniziare.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ...List.generate(
                    _selections.length,
                    (index) => _selectionCard(_selections[index], index),
                  ),
                if (_selections.length >= 2) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'QUANTE PARTITE VUOI TENERE?',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value:
                                    (_targetKeepCount <= 0
                                            ? _selections.length
                                            : _targetKeepCount)
                                        .clamp(2, _selections.length)
                                        .toDouble(),
                                min: 2,
                                max: _selections.length.toDouble(),
                                divisions: _selections.length - 2,
                                label:
                                    '${(_targetKeepCount <= 0 ? _selections.length : _targetKeepCount).clamp(2, _selections.length)}',
                                onChanged: _analyzing
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _targetKeepCount = value.round();
                                          _reviewResults.clear();
                                        });
                                      },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111827),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${(_targetKeepCount <= 0 ? _selections.length : _targetKeepCount).clamp(2, _selections.length)}',
                                style: const TextStyle(
                                  color: Color(0xFF00C853),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canAnalyze && !_analyzing
                        ? _analyzeCoupon
                        : null,
                    icon: _analyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.psychology),
                    label: Text(
                      _analyzing
                          ? 'ANALISI $_analysisProcessed / ${_selections.length}'
                          : 'ANALIZZA SCHEDINA',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (_reviewResults.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _analyzing ? null : _applyAiSuggestions,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text(
                        'APPLICA SUGGERIMENTI AI',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00C853),
                        side: const BorderSide(color: Color(0xFF00C853)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                const Text(
                  'Le selezioni vengono salvate automaticamente. '
                  'SmartBet mostrerà prima i suggerimenti e nessuna modifica '
                  'verrà applicata senza conferma.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }
}
