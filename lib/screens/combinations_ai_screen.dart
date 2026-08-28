import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import '../services/odds_service.dart';
import '../services/italy_schedule_filter.dart';
import '../services/smartbet_ai_service.dart';
import 'analysis_detail_screen.dart';

class CombinationsAiScreen extends StatefulWidget {
  const CombinationsAiScreen({super.key});

  @override
  State<CombinationsAiScreen> createState() => _CombinationsAiScreenState();
}

class _ComboChance {
  final String label;
  final int probability;

  const _ComboChance({required this.label, required this.probability});
}

class _CombinationCandidate {
  final MatchModel match;
  final AnalysisResult analysis;
  final String market;
  final int probability;
  final double? odd;
  final String? bookmaker;

  const _CombinationCandidate({
    required this.match,
    required this.analysis,
    required this.market,
    required this.probability,
    this.odd,
    this.bookmaker,
  });
}

class _CombinationsAiScreenState extends State<CombinationsAiScreen> {
  String _selectedMarket = 'X';
  int _topCount = 5;
  int _minimumSmartScore = 0;

  bool _loading = false;
  bool _italyScheduleOnly = true;
  bool _checkingOdds = false;
  int _processed = 0;
  int _total = 0;
  int _errors = 0;

  String? _errorMessage;

  final List<_CombinationCandidate> _results = [];

  final Set<int> _expandedComboFixtures = {};

  static const int _batchSize = 3;
  static const double _minimumOdd = 1.15;

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
    'COMBO CHANCE',
  ];

  // ============================================================
  // MARKET PROBABILITY
  // ============================================================

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

  // ============================================================
  // COMBO CHANCE
  // ============================================================

  double _poissonProbability(double lambda, int goals) {
    if (lambda <= 0 || goals < 0) {
      return 0.0;
    }

    var factorial = 1;

    for (var i = 2; i <= goals; i++) {
      factorial *= i;
    }

    return math.pow(lambda, goals).toDouble() * math.exp(-lambda) / factorial;
  }

  List<_ComboChance> _comboChances(AnalysisResult result) {
    final homeLambda = result.expectedHomeGoals;
    final awayLambda = result.expectedAwayGoals;

    if (homeLambda <= 0 || awayLambda <= 0) {
      return const [];
    }

    const maxGoals = 8;

    final scores = <({int home, int away, double probability})>[];

    var totalMass = 0.0;

    for (var home = 0; home <= maxGoals; home++) {
      final homeProbability = _poissonProbability(homeLambda, home);

      for (var away = 0; away <= maxGoals; away++) {
        final awayProbability = _poissonProbability(awayLambda, away);

        final probability = homeProbability * awayProbability;

        totalMass += probability;

        scores.add((home: home, away: away, probability: probability));
      }
    }

    if (totalMass <= 0) {
      return const [];
    }

    int probabilityWhere(bool Function(int home, int away) condition) {
      var probability = 0.0;

      for (final score in scores) {
        if (condition(score.home, score.away)) {
          probability += score.probability;
        }
      }

      return ((probability / totalMass) * 100).round().clamp(0, 100);
    }

    final combos = <_ComboChance>[
      _ComboChance(
        label: '1X + O1.5',
        probability: probabilityWhere(
          (home, away) => home >= away && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: 'X2 + O1.5',
        probability: probabilityWhere(
          (home, away) => away >= home && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: '1 + O1.5',
        probability: probabilityWhere(
          (home, away) => home > away && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: '2 + O1.5',
        probability: probabilityWhere(
          (home, away) => away > home && home + away >= 2,
        ),
      ),
      _ComboChance(
        label: '1X + U3.5',
        probability: probabilityWhere(
          (home, away) => home >= away && home + away <= 3,
        ),
      ),
      _ComboChance(
        label: 'X2 + U3.5',
        probability: probabilityWhere(
          (home, away) => away >= home && home + away <= 3,
        ),
      ),
      _ComboChance(
        label: '1 + GOAL',
        probability: probabilityWhere(
          (home, away) => home > away && home > 0 && away > 0,
        ),
      ),
      _ComboChance(
        label: '2 + GOAL',
        probability: probabilityWhere(
          (home, away) => away > home && home > 0 && away > 0,
        ),
      ),
      _ComboChance(
        label: '1 + NO GOAL',
        probability: probabilityWhere(
          (home, away) => home > away && (home == 0 || away == 0),
        ),
      ),
      _ComboChance(
        label: '2 + NO GOAL',
        probability: probabilityWhere(
          (home, away) => away > home && (home == 0 || away == 0),
        ),
      ),
      _ComboChance(
        label: 'GOAL + O2.5',
        probability: probabilityWhere(
          (home, away) => home > 0 && away > 0 && home + away >= 3,
        ),
      ),
      _ComboChance(
        label: 'NO GOAL + U2.5',
        probability: probabilityWhere(
          (home, away) => (home == 0 || away == 0) && home + away <= 2,
        ),
      ),
    ];

    // Non mostriamo combinazioni statisticamente troppo deboli.
    final reliable = combos.where((combo) => combo.probability >= 30).toList();

    reliable.sort((a, b) => b.probability.compareTo(a.probability));

    return reliable;
  }

  Widget _comboChanceSection(AnalysisResult result, int fixtureId) {
    final combos = _comboChances(result);

    if (combos.isEmpty) {
      return const SizedBox.shrink();
    }

    final expanded = _expandedComboFixtures.contains(fixtureId);

    final visible = expanded ? combos : combos.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(Icons.hub_outlined, size: 16, color: Color(0xFF00C853)),
            SizedBox(width: 6),
            Text(
              'COMBO CHANCE',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visible.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 7,
            mainAxisSpacing: 7,
            childAspectRatio: 1.75,
          ),
          itemBuilder: (context, index) {
            final combo = visible[index];

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00C853).withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    combo.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${combo.probability}%',
                    style: const TextStyle(
                      color: Color(0xFF00C853),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (combos.length > 6) ...[
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() {
                  if (expanded) {
                    _expandedComboFixtures.remove(fixtureId);
                  } else {
                    _expandedComboFixtures.add(fixtureId);
                  }
                });
              },
              child: Text(
                expanded ? 'MOSTRA MENO' : 'MOSTRA TUTTE',
                style: const TextStyle(
                  color: Color(0xFF00C853),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        const Text(
          'Probabilità congiunte stimate dal modello '
          'sulla distribuzione dei possibili punteggi.',
          style: TextStyle(color: Colors.white30, fontSize: 9, height: 1.3),
        ),
      ],
    );
  }

  // ============================================================
  // PARTITA NON INIZIATA
  // ============================================================

  bool _isUpcoming(MatchModel match) {
    try {
      return DateTime.parse(match.date).toLocal().isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // SCANSIONE
  // ============================================================

  Future<void> _findCombinations() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _checkingOdds = false;
      _processed = 0;
      _total = 0;
      _errors = 0;
      _errorMessage = null;
      _results.clear();
    });

    try {
      final allMatches = await MatchRepository.getTodayMatches();

      final matches = allMatches
          .where(
            (match) =>
                match.hasTeamIds &&
                _isUpcoming(match) &&
                (!_italyScheduleOnly || ItalyScheduleFilter.allows(match)),
          )
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _total = matches.length;
      });

      final allCandidates = <_CombinationCandidate>[];

      for (var start = 0; start < matches.length; start += _batchSize) {
        if (!mounted) {
          return;
        }

        final end = (start + _batchSize).clamp(0, matches.length);

        final batch = matches.sublist(start, end);

        final analyzed = await Future.wait(
          batch.map((match) async {
            try {
              final analysis = await SmartCore.analyze(match);

              if (_selectedMarket == 'COMBO CHANCE') {
                final combos = _comboChances(analysis);

                if (combos.isEmpty) {
                  return null;
                }

                final bestCombo = combos.first;

                return _CombinationCandidate(
                  match: match,
                  analysis: analysis,
                  market: bestCombo.label,
                  probability: bestCombo.probability,
                );
              }

              final probability = _probabilityFor(analysis, _selectedMarket);

              return _CombinationCandidate(
                match: match,
                analysis: analysis,
                market: _selectedMarket,
                probability: probability,
              );
            } catch (_) {
              return null;
            }
          }),
        );

        var batchErrors = 0;

        for (final item in analyzed) {
          if (item == null) {
            batchErrors++;
            continue;
          }

          if (item.probability <= 0) {
            continue;
          }

          if (item.analysis.smartScore < _minimumSmartScore) {
            continue;
          }

          allCandidates.add(item);
        }

        allCandidates.sort((a, b) {
          final probabilityCompare = b.probability.compareTo(a.probability);

          if (probabilityCompare != 0) {
            return probabilityCompare;
          }

          return b.analysis.smartScore.compareTo(a.analysis.smartScore);
        });

        if (!mounted) {
          return;
        }

        setState(() {
          _processed = end;
          _errors += batchErrors;
        });
      }

      if (!mounted) {
        return;
      }

      allCandidates.sort((a, b) {
        final probabilityCompare = b.probability.compareTo(a.probability);

        if (probabilityCompare != 0) {
          return probabilityCompare;
        }

        return b.analysis.smartScore.compareTo(a.analysis.smartScore);
      });

      setState(() {
        _checkingOdds = true;
      });

      final oddsService = OddsService();
      final validCandidates = <_CombinationCandidate>[];

      try {
        for (final item in allCandidates) {
          if (!mounted || validCandidates.length >= _topCount) {
            break;
          }

          if (_selectedMarket == 'COMBO CHANCE') {
            validCandidates.add(item);

            if (!mounted) {
              return;
            }

            setState(() {
              _results
                ..clear()
                ..addAll(validCandidates);
            });

            continue;
          }

          final marketOdds = await oddsService.getFixtureMarketOdds(
            fixtureId: item.match.fixtureId,
          );

          final bestOdd = marketOdds?.oddFor(item.market);

          // Quota assente o inferiore a 1.20: selezione esclusa.
          if (bestOdd == null || bestOdd.odd < _minimumOdd) {
            continue;
          }

          validCandidates.add(
            _CombinationCandidate(
              match: item.match,
              analysis: item.analysis,
              market: item.market,
              probability: item.probability,
              odd: bestOdd.odd,
              bookmaker: bestOdd.bookmakerName,
            ),
          );

          if (!mounted) {
            return;
          }

          setState(() {
            _results
              ..clear()
              ..addAll(validCandidates);
          });
        }
      } finally {
        oddsService.dispose();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _checkingOdds = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _checkingOdds = false;
        _loading = false;
        _errorMessage = _friendlyErrorMessage(e);
      });
    }
  }

  // ============================================================
  // ERRORI
  // ============================================================

  String _friendlyErrorMessage(Object? error) {
    final raw = error?.toString().toLowerCase() ?? '';

    if (raw.contains('failed host lookup') ||
        raw.contains('socketexception') ||
        raw.contains('network is unreachable') ||
        raw.contains('connection refused') ||
        raw.contains('connection reset') ||
        raw.contains('no route to host')) {
      return 'Impossibile collegarsi al servizio dati. '
          'Controlla la connessione internet e riprova.';
    }

    if (raw.contains('timeout') || raw.contains('timed out')) {
      return 'Il servizio sta impiegando troppo tempo '
          'a rispondere. Riprova tra qualche istante.';
    }

    if (raw.contains('429') ||
        raw.contains('too many requests') ||
        raw.contains('rate limit')) {
      return 'Il servizio dati è temporaneamente '
          'occupato. Attendi qualche istante e riprova.';
    }

    return 'Si è verificato un problema durante '
        'la ricerca. Riprova tra poco.';
  }

  // ============================================================
  // ANALISI AVANZATA
  // ============================================================

  Future<void> _openAdvancedAnalysis(MatchModel match) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const AlertDialog(
          backgroundColor: Color(0xFF1F2937),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'SMARTBET AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Analisi avanzata della partita in corso...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
      },
    );

    try {
      final advancedResult = await SmartBetAiService().analyzeMatch(match);

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      if (!mounted) {
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AnalysisDetailScreen(match: match, result: advancedResult),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyErrorMessage(e))));
    }
  }

  // ============================================================
  // FORMAT
  // ============================================================

  String _formatDate(String date) {
    if (date.isEmpty) {
      return '';
    }

    try {
      final parsed = DateTime.parse(date).toLocal();

      final hour = parsed.hour.toString().padLeft(2, '0');
      final minute = parsed.minute.toString().padLeft(2, '0');

      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  Color _scoreColor(int score) {
    if (score >= 75) {
      return Colors.greenAccent;
    }

    if (score >= 60) {
      return Colors.orangeAccent;
    }

    return Colors.white54;
  }

  // ============================================================
  // SELECTORS
  // ============================================================

  Widget _marketSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _markets.map((market) {
        final selected = _selectedMarket == market;

        return ChoiceChip(
          label: Text(market),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _selectedMarket = market;
              _results.clear();
            });
          },
          selectedColor: const Color(0xFF00C853),
          backgroundColor: const Color(0xFF1F2937),
          showCheckmark: false,
          side: BorderSide(
            color: selected ? const Color(0xFF00C853) : Colors.white12,
          ),
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        );
      }).toList(),
    );
  }

  Widget _smartScoreSelector() {
    Widget chip(String label, int score) {
      final selected = _minimumSmartScore == score;

      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _minimumSmartScore = score;
            _results.clear();
          });
        },
        selectedColor: const Color(0xFF00C853),
        backgroundColor: const Color(0xFF1F2937),
        showCheckmark: false,
        side: BorderSide(
          color: selected ? const Color(0xFF00C853) : Colors.white12,
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Qualsiasi score', 0),
          const SizedBox(width: 7),
          chip('≥55', 55),
          const SizedBox(width: 7),
          chip('≥60', 60),
          const SizedBox(width: 7),
          chip('≥65', 65),
        ],
      ),
    );
  }

  // ============================================================
  // RESULT CARD
  // ============================================================

  Widget _resultCard(_CombinationCandidate item, int rank) {
    final result = item.analysis;
    final match = item.match;
    final scoreColor = _scoreColor(result.smartScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF00C853).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${match.country} • '
                      '${match.league} • '
                      '${_formatDate(match.date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      Text(
                        item.market,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.probability}%',
                        style: const TextStyle(
                          color: Color(0xFF00C853),
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'SMART SCORE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${result.smartScore}',
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          _comboChanceSection(result, match.fixtureId),

          const SizedBox(height: 10),

          if (item.odd != null) ...[
            Text(
              'Quota: ${item.odd!.toStringAsFixed(2)}'
              '${item.bookmaker?.trim().isNotEmpty == true ? ' • ${item.bookmaker}' : ''}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
          ] else if (_selectedMarket == 'COMBO CHANCE') ...[
            const Text(
              'Quota combo bookmaker non disponibile',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
          ],

          Text(
            'Rischio pre-analisi: ${result.risk}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openAdvancedAnalysis(match),
              icon: const Icon(Icons.psychology, size: 18),
              label: const Text(
                'ANALIZZA PARTITA',
                style: TextStyle(fontWeight: FontWeight.bold),
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
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Combinazioni AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF00C853), size: 29),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Trova le combinazioni migliori',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          const Text(
            'Scegli un mercato e SmartBet '
            'scansionerà le partite di oggi, '
            'mostrando quelle con la probabilità '
            'più alta nella pre-analisi.',
            style: TextStyle(color: Colors.white54, height: 1.4),
          ),

          const SizedBox(height: 8),

          Text(
            _selectedMarket == 'COMBO CHANCE'
                ? 'Filtro automatico: migliori Combo Chance per probabilità stimata.'
                : 'Filtro automatico: solo selezioni con quota reale almeno 1.15.',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 11,
              height: 1.35,
            ),
          ),

          const SizedBox(height: 14),

          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: SwitchListTile(
              value: _italyScheduleOnly,
              activeThumbColor: const Color(0xFF00C853),
              title: const Text(
                'Palinsesto Italia',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _italyScheduleOnly
                    ? 'Competizioni principali più vicine ai palinsesti dei bookmaker italiani.'
                    : 'Tutte le competizioni disponibili.',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onChanged: (_loading || _checkingOdds)
                  ? null
                  : (value) {
                      setState(() {
                        _italyScheduleOnly = value;
                        _results.clear();
                        _errorMessage = null;
                        _processed = 0;
                        _total = 0;
                      });
                    },
            ),
          ),

          const SizedBox(height: 22),

          const Text(
            'COSA VUOI TROVARE?',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),

          const SizedBox(height: 10),

          _marketSelector(),

          const SizedBox(height: 20),

          const Text(
            'AFFIDABILITÀ MINIMA',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),

          const SizedBox(height: 8),

          _smartScoreSelector(),

          const SizedBox(height: 20),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'NUMERO RISULTATI',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C853).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '$_topCount partite',
                  style: const TextStyle(
                    color: Color(0xFF00C853),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Slider(
            value: _topCount.toDouble(),
            min: 3,
            max: 15,
            divisions: 12,
            label: '$_topCount',
            onChanged: _loading
                ? null
                : (value) {
                    setState(() {
                      _topCount = value.round();
                      _results.clear();
                    });
                  },
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('3', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('10', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _findCombinations,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.manage_search),
              label: Text(
                _loading
                    ? 'RICERCA IN CORSO...'
                    : 'TROVA LE MIGLIORI '
                          '$_selectedMarket',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          if (_loading) ...[
            const SizedBox(height: 15),
            LinearProgressIndicator(
              value: _total > 0 ? (_processed / _total).clamp(0.0, 1.0) : null,
              minHeight: 7,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(height: 7),
            Text(
              _checkingOdds
                  ? 'Controllo quote reali ≥ 1.15...'
                  : _total > 0
                  ? 'Analizzate $_processed / '
                        '$_total partite'
                  : 'Caricamento partite...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud_off, color: Colors.orangeAccent),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, height: 1.4),
                  ),
                ],
              ),
            ),
          ],

          if (_results.isNotEmpty) ...[
            const SizedBox(height: 24),

            Row(
              children: [
                Text(
                  'TOP ${_results.length} '
                  '$_selectedMarket',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (!_loading)
                  const Text(
                    'PRE-ANALISI',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            ...List.generate(
              _results.length,
              (index) => _resultCard(_results[index], index + 1),
            ),
          ],

          if (!_loading &&
              _results.isEmpty &&
              _processed > 0 &&
              _errorMessage == null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Nessun risultato disponibile '
                'per $_selectedMarket con i '
                'filtri scelti e quota minima 1.15.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, height: 1.4),
              ),
            ),
          ],

          if (!_loading && _errors > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$_errors partite non sono state '
              'analizzate per dati insufficienti '
              'o errore temporaneo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
            ),
          ],

          const SizedBox(height: 14),

          const Text(
            'Le percentuali mostrate sono stime '
            'della pre-analisi statistica e non '
            'garantiscono l’esito della partita.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }
}
