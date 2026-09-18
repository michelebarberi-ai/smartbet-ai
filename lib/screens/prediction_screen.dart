import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import '../services/italy_schedule_filter.dart';
import '../services/odds_service.dart';
import '../services/smartbet_ai_service.dart';
import '../services/smartbet_market_probability_service.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  final OddsService _oddsService = OddsService();
  final SmartBetAiService _aiService = SmartBetAiService();

  bool _loading = false;
  String? _error;

  String _phase = '';
  int _processed = 0;
  int _total = 0;

  final List<_DailyPick> _results = [];

  static const int _wantedResults = 3;
  static const int _maximumMatchesToAnalyze = 36;
  static const int _preBatchSize = 6;
  static const int _auditBatchSize = 4;
  static const int _oddsBatchSize = 6;
  static const double _minimumOdd = 1.25;

  static const List<String> _marketOrder = [
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
    'OVER 3.5',
    'UNDER 3.5',
    'OVER 4.5',
    'UNDER 4.5',
    'CASA SEGNA',
    'OSPITE SEGNA',
    'GOAL + O2.5',
    'NO GOAL + U2.5',
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generate();
    });
  }

  @override
  void dispose() {
    _oddsService.dispose();
    _aiService.dispose();
    super.dispose();
  }

  // ============================================================
  // PROBABILITÀ MERCATI
  // ============================================================

  Map<String, int> _markets(AnalysisResult result) {
    final values = <String, int>{
      '1': result.homeProbability,
      'X': result.drawProbability,
      '2': result.awayProbability,
      '1X': (result.homeProbability + result.drawProbability).clamp(0, 100),
      'X2': (result.drawProbability + result.awayProbability).clamp(0, 100),
      '12': (result.homeProbability + result.awayProbability).clamp(0, 100),
      'OVER 1.5': result.over15Probability,
      'UNDER 1.5': result.under15Probability,
      'OVER 2.5': result.over25Probability,
      'UNDER 2.5': result.under25Probability,
      'GOAL': result.goalProbability,
      'NO GOAL': result.noGoalProbability,
    };

    for (final market in _marketOrder) {
      if (values.containsKey(market)) {
        continue;
      }

      values[market] = SmartBetMarketProbabilityService.probabilityFor(
        result,
        market,
      );
    }

    return values;
  }

  int _bestStatisticalProbability(AnalysisResult analysis) {
    var best = 0;

    for (final market in _marketOrder) {
      final value = _markets(analysis)[market] ?? 0;
      if (value > best) {
        best = value;
      }
    }

    return best;
  }

  // ============================================================
  // RISULTATI ESATTI STIMATI
  // ============================================================

  List<_ExactScoreEstimate> _exactScoreEstimates(AnalysisResult analysis) {
    var homeLambda = analysis.expectedHomeGoals;
    var awayLambda = analysis.expectedAwayGoals;

    // Fallback prudente se l'analisi non espone xG validi.
    if (homeLambda <= 0 || awayLambda <= 0) {
      final total = _fallbackTotalGoals(analysis);
      final homeAwayTotal = math.max(
        1.0,
        analysis.homeProbability + analysis.awayProbability.toDouble(),
      );

      final rawHomeShare = analysis.homeProbability / homeAwayTotal;
      final decisiveness = (1.0 - analysis.drawProbability / 100.0)
          .clamp(0.45, 0.90)
          .toDouble();

      var homeShare = 0.5 + (rawHomeShare - 0.5) * decisiveness;
      homeShare = homeShare.clamp(0.27, 0.73).toDouble();

      homeLambda = total * homeShare;
      awayLambda = total - homeLambda;
    }

    final scores = <_ExactScoreEstimate>[];

    for (var home = 0; home <= 8; home++) {
      for (var away = 0; away <= 8; away++) {
        scores.add(
          _ExactScoreEstimate(
            homeGoals: home,
            awayGoals: away,
            probability:
                _poisson(home, homeLambda) * _poisson(away, awayLambda),
          ),
        );
      }
    }

    final totalMass = scores.fold<double>(
      0.0,
      (sum, item) => sum + item.probability,
    );

    final normalized = scores
        .map(
          (item) => _ExactScoreEstimate(
            homeGoals: item.homeGoals,
            awayGoals: item.awayGoals,
            probability: totalMass > 0
                ? item.probability / totalMass
                : item.probability,
          ),
        )
        .toList();

    normalized.sort((a, b) => b.probability.compareTo(a.probability));

    return normalized.take(3).toList();
  }

  double _fallbackTotalGoals(AnalysisResult analysis) {
    final over25 = analysis.over25Probability / 100.0;
    final over15 = analysis.over15Probability / 100.0;

    var total = 2.45;

    if (over25 >= 0.70) {
      total += 0.65;
    } else if (over25 >= 0.58) {
      total += 0.35;
    } else if (over25 <= 0.38) {
      total -= 0.35;
    }

    if (over15 >= 0.80) {
      total += 0.20;
    } else if (over15 <= 0.55) {
      total -= 0.20;
    }

    return total.clamp(1.20, 4.50).toDouble();
  }

  double _poisson(int goals, double lambda) {
    var factorial = 1.0;

    for (var i = 2; i <= goals; i++) {
      factorial *= i;
    }

    return math.exp(-lambda) * math.pow(lambda, goals).toDouble() / factorial;
  }

  // ============================================================
  // AUDITOR
  // ============================================================

  String _auditStatus(AnalysisResult analysis) {
    final explanation = analysis.explanation.toUpperCase();
    final risk = analysis.risk.toUpperCase();

    if (explanation.contains('STATO: STRONG_CONTRADICTION') ||
        risk.contains('FORTE DISCORDANZA')) {
      return 'STRONG_CONTRADICTION';
    }

    if (explanation.contains('STATO: DOUBT') ||
        risk.contains('AUDITOR: CON RISERVA')) {
      return 'DOUBT';
    }

    return 'CONFIRM';
  }

  bool _auditStrongContradiction(AnalysisResult analysis) {
    return _auditStatus(analysis) == 'STRONG_CONTRADICTION';
  }

  bool _auditDoubt(AnalysisResult analysis) {
    return _auditStatus(analysis) == 'DOUBT';
  }

  String _normalizeAuditMarket(String value) {
    return value
        .toUpperCase()
        .replaceAll('OVER', 'O')
        .replaceAll('UNDER', 'U')
        .replaceAll('NO GOAL', 'NOGOAL')
        .replaceAll('BTTS YES', 'GOAL')
        .replaceAll('BTTS NO', 'NOGOAL')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  bool _auditorBlocksMarket(AnalysisResult analysis, String market) {
    final line = analysis.explanation
        .split(String.fromCharCode(10))
        .where(
          (item) => item.trim().toLowerCase().startsWith('mercati bloccati:'),
        )
        .cast<String?>()
        .firstWhere((item) => item != null, orElse: () => null);

    if (line == null) {
      return false;
    }

    final raw = line.split(':').skip(1).join(':').trim();

    if (raw.isEmpty || raw.toLowerCase() == 'nessuno') {
      return false;
    }

    final wanted = _normalizeAuditMarket(market);

    final blocked = raw
        .split(',')
        .map((item) => _normalizeAuditMarket(item))
        .where((item) => item.isNotEmpty)
        .toSet();

    return blocked.contains(wanted);
  }

  // ============================================================
  // QUALITÀ / RANKING
  // ============================================================

  double _rankScore({
    required int probability,
    required int smartScore,
    required double edge,
    required double expectedValue,
    required bool doubt,
  }) {
    final edgePoints = edge * 100.0;
    final evPoints = expectedValue * 100.0;

    final base =
        probability * 0.54 +
        smartScore * 0.22 +
        edgePoints.clamp(-8.0, 18.0).toDouble() * 0.10 +
        evPoints.clamp(-10.0, 25.0).toDouble() * 0.14;

    return base - (doubt ? 6.0 : 0.0);
  }

  bool _passesPrimary({
    required int probability,
    required int smartScore,
    required double odd,
    required double expectedValue,
  }) {
    return probability >= 58 &&
        smartScore >= 55 &&
        odd >= _minimumOdd &&
        odd <= 4.50 &&
        expectedValue >= -0.03;
  }

  bool _passesAdaptive({
    required int probability,
    required int smartScore,
    required double odd,
    required double expectedValue,
  }) {
    return probability >= 52 &&
        smartScore >= 50 &&
        odd >= _minimumOdd &&
        odd <= 5.50 &&
        expectedValue >= -0.10;
  }

  _DailyPick? _bestPickForMatch({
    required MatchModel match,
    required AnalysisResult analysis,
    required FixtureMarketOdds? odds,
  }) {
    if (_auditStrongContradiction(analysis) || odds == null) {
      return null;
    }

    final probabilities = _markets(analysis);
    final exactScores = _exactScoreEstimates(analysis);
    final primary = <_DailyPick>[];
    final adaptive = <_DailyPick>[];
    final doubt = _auditDoubt(analysis);

    for (final market in _marketOrder) {
      if (_auditorBlocksMarket(analysis, market)) {
        continue;
      }

      final probability = probabilities[market] ?? 0;
      final bestOdd = odds.oddFor(market);

      if (probability <= 0 || bestOdd == null || bestOdd.odd < _minimumOdd) {
        continue;
      }

      final p = probability / 100.0;
      final impliedProbability = 1.0 / bestOdd.odd;
      final edge = p - impliedProbability;
      final expectedValue = (p * bestOdd.odd) - 1.0;

      final pick = _DailyPick(
        match: match,
        analysis: analysis,
        market: market,
        probability: probability,
        odd: bestOdd.odd,
        bookmaker: bestOdd.bookmakerName,
        edge: edge,
        expectedValue: expectedValue,
        rankScore: _rankScore(
          probability: probability,
          smartScore: analysis.smartScore,
          edge: edge,
          expectedValue: expectedValue,
          doubt: doubt,
        ),
        auditStatus: _auditStatus(analysis),
        exactPrimary: exactScores[0],
        exactAlternative: exactScores[1],
        exactThird: exactScores[2],
      );

      if (_passesPrimary(
        probability: probability,
        smartScore: analysis.smartScore,
        odd: bestOdd.odd,
        expectedValue: expectedValue,
      )) {
        primary.add(pick);
        continue;
      }

      if (_passesAdaptive(
        probability: probability,
        smartScore: analysis.smartScore,
        odd: bestOdd.odd,
        expectedValue: expectedValue,
      )) {
        adaptive.add(pick);
      }
    }

    int compare(_DailyPick a, _DailyPick b) {
      final score = b.rankScore.compareTo(a.rankScore);
      if (score != 0) {
        return score;
      }

      final probability = b.probability.compareTo(a.probability);
      if (probability != 0) {
        return probability;
      }

      return b.analysis.smartScore.compareTo(a.analysis.smartScore);
    }

    primary.sort(compare);
    adaptive.sort(compare);

    if (primary.isNotEmpty) {
      return primary.first;
    }

    if (adaptive.isNotEmpty) {
      return adaptive.first;
    }

    return null;
  }

  List<_DailyPick> _topSnapshot(List<_DailyPick> source) {
    final ranked = List<_DailyPick>.of(source);

    ranked.sort((a, b) {
      final score = b.rankScore.compareTo(a.rankScore);
      if (score != 0) {
        return score;
      }

      final probability = b.probability.compareTo(a.probability);
      if (probability != 0) {
        return probability;
      }

      return b.analysis.smartScore.compareTo(a.analysis.smartScore);
    });

    return ranked.take(_wantedResults).toList();
  }

  // ============================================================
  // GENERAZIONE
  // ============================================================

  Future<void> _generate() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _phase = 'matches';
      _processed = 0;
      _total = 0;
      _results.clear();
    });

    try {
      final allMatches = await MatchRepository.getTodayMatches();

      final matches = allMatches
          .where(
            (match) =>
                match.hasTeamIds &&
                _isUpcoming(match) &&
                ItalyScheduleFilter.allows(match),
          )
          .toList();

      matches.sort((a, b) => b.aiWeight.compareTo(a.aiWeight));

      final amount = math.min(matches.length, _maximumMatchesToAnalyze);
      final selectedMatches = matches.take(amount).toList();

      if (!mounted) {
        return;
      }

      if (selectedMatches.isEmpty) {
        setState(() {
          _loading = false;
          _phase = '';
          _error = 'Non ci sono partite disponibili nel Palinsesto Italia.';
        });
        return;
      }

      setState(() {
        _phase = 'scan';
        _processed = 0;
        _total = selectedMatches.length;
      });

      final preliminary = <_PreCandidate>[];

      for (
        var start = 0;
        start < selectedMatches.length;
        start += _preBatchSize
      ) {
        final end = math.min(start + _preBatchSize, selectedMatches.length);
        final batch = selectedMatches.sublist(start, end);

        final analyzed = await Future.wait(
          batch.map((match) async {
            try {
              final analysis = await SmartCore.analyze(match);

              if (analysis.smartScore <= 0) {
                return null;
              }

              return _PreCandidate(
                match: match,
                analysis: analysis,
                bestProbability: _bestStatisticalProbability(analysis),
              );
            } catch (_) {
              return null;
            }
          }),
        );

        preliminary.addAll(analyzed.whereType<_PreCandidate>());

        if (!mounted) {
          return;
        }

        setState(() {
          _processed = end;
        });
      }

      if (preliminary.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _loading = false;
          _phase = '';
          _error =
              'SmartBet non ha trovato candidate statistiche utilizzabili.';
        });
        return;
      }

      preliminary.sort((a, b) {
        final probability = b.bestProbability.compareTo(a.bestProbability);
        if (probability != 0) {
          return probability;
        }

        return b.analysis.smartScore.compareTo(a.analysis.smartScore);
      });

      final firstShortlistSize = math.min(preliminary.length, 12);
      final firstShortlist = preliminary.take(firstShortlistSize).toList();

      final audited = <_PreCandidate>[];
      var completedAdvanced = 0;

      if (!mounted) {
        return;
      }

      setState(() {
        _phase = 'audit';
        _processed = 0;
        _total = firstShortlist.length;
      });

      for (
        var start = 0;
        start < firstShortlist.length;
        start += _auditBatchSize
      ) {
        final end = math.min(start + _auditBatchSize, firstShortlist.length);
        final batch = firstShortlist.sublist(start, end);

        final advanced = await Future.wait(
          batch.map((candidate) async {
            try {
              final result = await _aiService.analyzeMatch(candidate.match);

              if (result.smartScore <= 0 || _auditStrongContradiction(result)) {
                return null;
              }

              return _PreCandidate(
                match: candidate.match,
                analysis: result,
                bestProbability: _bestStatisticalProbability(result),
              );
            } catch (_) {
              return null;
            } finally {
              completedAdvanced++;

              if (mounted) {
                setState(() {
                  _processed = math.min(completedAdvanced, _total);
                });
              }
            }
          }),
        );

        audited.addAll(advanced.whereType<_PreCandidate>());

        if (!mounted) {
          return;
        }
      }

      final qualified = <_DailyPick>[];

      if (!mounted) {
        return;
      }

      setState(() {
        _phase = 'odds';
        _processed = 0;
        _total = audited.length;
      });

      for (var start = 0; start < audited.length; start += _oddsBatchSize) {
        final end = math.min(start + _oddsBatchSize, audited.length);
        final batch = audited.sublist(start, end);

        final priced = await Future.wait(
          batch.map((candidate) async {
            try {
              final odds = await _oddsService.getFixtureMarketOdds(
                fixtureId: candidate.match.fixtureId,
              );

              return _bestPickForMatch(
                match: candidate.match,
                analysis: candidate.analysis,
                odds: odds,
              );
            } catch (_) {
              return null;
            }
          }),
        );

        qualified.addAll(priced.whereType<_DailyPick>());
        final live = _topSnapshot(qualified);

        if (!mounted) {
          return;
        }

        setState(() {
          _processed = end;
          _results
            ..clear()
            ..addAll(live);
        });
      }

      // Recovery: solo se le prime 12 candidate non bastano.
      if (qualified.length < _wantedResults &&
          preliminary.length > firstShortlistSize) {
        final remaining = preliminary.skip(firstShortlistSize).take(8).toList();

        if (remaining.isNotEmpty) {
          if (!mounted) {
            return;
          }

          setState(() {
            _phase = 'recovery';
            _processed = 0;
            _total = remaining.length;
          });

          for (
            var start = 0;
            start < remaining.length && qualified.length < _wantedResults;
            start += _auditBatchSize
          ) {
            final end = math.min(start + _auditBatchSize, remaining.length);
            final batch = remaining.sublist(start, end);

            final recovered = await Future.wait(
              batch.map((candidate) async {
                try {
                  final result = await _aiService.analyzeMatch(candidate.match);

                  if (result.smartScore <= 0 ||
                      _auditStrongContradiction(result)) {
                    return null;
                  }

                  final odds = await _oddsService.getFixtureMarketOdds(
                    fixtureId: candidate.match.fixtureId,
                  );

                  return _bestPickForMatch(
                    match: candidate.match,
                    analysis: result,
                    odds: odds,
                  );
                } catch (_) {
                  return null;
                }
              }),
            );

            qualified.addAll(recovered.whereType<_DailyPick>());
            final live = _topSnapshot(qualified);

            if (!mounted) {
              return;
            }

            setState(() {
              _processed = end;
              _results
                ..clear()
                ..addAll(live);
            });
          }
        }
      }

      final finalResults = _topSnapshot(qualified);

      if (!mounted) {
        return;
      }

      setState(() {
        _results
          ..clear()
          ..addAll(finalResults);
        _loading = false;
        _phase = '';

        if (_results.isEmpty) {
          _error =
              'SmartBet non ha trovato selezioni del giorno con qualità, '
              'Auditor e quota reale sufficienti.';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _phase = '';
        _error =
            'Non è stato possibile generare i risultati del giorno. '
            'Riprova tra poco.';
      });
    }
  }

  // ============================================================
  // UTILITY
  // ============================================================

  bool _isUpcoming(MatchModel match) {
    final parsed = DateTime.tryParse(match.date);

    if (parsed == null) {
      return true;
    }

    return parsed.toLocal().isAfter(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
  }

  String _competitionLabel(MatchModel match) {
    final country = match.country.trim();
    final league = match.league.trim();

    if (country.isNotEmpty && league.isNotEmpty) {
      return '$country • $league';
    }

    if (league.isNotEmpty) {
      return league;
    }

    return country;
  }

  String _matchTime(MatchModel match) {
    final date = DateTime.tryParse(match.date);

    if (date == null) {
      return '';
    }

    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  Color _scoreColor(int score) {
    if (score >= 70) {
      return Colors.greenAccent;
    }

    if (score >= 55) {
      return Colors.orangeAccent;
    }

    return Colors.white70;
  }

  String _auditLabel(_DailyPick item) {
    switch (item.auditStatus) {
      case 'DOUBT':
        return 'CON RISERVA';
      case 'CONFIRM':
        return 'CONFERMATA';
      default:
        return 'VERIFICATA';
    }
  }

  Color _auditColor(_DailyPick item) {
    return item.auditStatus == 'DOUBT'
        ? Colors.orangeAccent
        : const Color(0xFF00C853);
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _resultCard(_DailyPick item, int position) {
    final scoreColor = _scoreColor(item.analysis.smartScore);
    final auditColor = _auditColor(item);
    final competition = _competitionLabel(item.match);
    final time = _matchTime(item.match);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(17),
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
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$position',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  competition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '${item.match.homeTeam} - ${item.match.awayTeam}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _mainValueBox(
                  label: 'SCELTA SMARTBET',
                  value: item.market,
                  valueColor: const Color(0xFF00C853),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _mainValueBox(
                  label: 'PROBABILITÀ',
                  value: '${item.probability}%',
                  valueColor: const Color(0xFF00C853),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_offer_outlined,
                  color: Colors.white54,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Text(
                  '@ ${item.odd.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item.bookmaker,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _infoBox(
                  'Smart Score',
                  '${item.analysis.smartScore}',
                  valueColor: scoreColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _infoBox(
                  'Auditor',
                  _auditLabel(item),
                  valueColor: auditColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.scoreboard_outlined, size: 17, color: Colors.white54),
              SizedBox(width: 7),
              Text(
                'RISULTATI ESATTI STIMATI',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _exactScoreBox(
                  label: '1°',
                  score: item.exactPrimary.label,
                  probability: item.exactPrimary.probability,
                  primary: true,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _exactScoreBox(
                  label: '2°',
                  score: item.exactAlternative.label,
                  probability: item.exactAlternative.probability,
                  primary: false,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _exactScoreBox(
                  label: '3°',
                  score: item.exactThird.label,
                  probability: item.exactThird.probability,
                  primary: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Gli score esatti sono scenari statistici del modello e hanno '
            'naturalmente probabilità inferiori rispetto al mercato principale.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Rischio: ${item.analysis.risk}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _mainValueBox({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _exactScoreBox({
    required String label,
    required String score,
    required double probability,
    required bool primary,
  }) {
    final accent = primary ? const Color(0xFF00C853) : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            score,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(probability * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 9.5),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROGRESS
  // ============================================================

  Widget _progressCard() {
    String title;
    String subtitle;

    switch (_phase) {
      case 'scan':
        title = 'Scansione statistica: $_processed / $_total';
        subtitle = 'SmartCore confronta le partite del Palinsesto Italia.';
        break;
      case 'audit':
        title = 'SmartBet + Auditor: $_processed / $_total';
        subtitle = 'Secondo controllo indipendente sulle candidate migliori.';
        break;
      case 'odds':
        title =
            'Quote + selezione: $_processed / $_total • ${_results.length}/$_wantedResults trovate';
        subtitle = 'Le migliori selezioni valide compaiono appena disponibili.';
        break;
      case 'recovery':
        title =
            'Ricerca alternative: $_processed / $_total • ${_results.length}/$_wantedResults trovate';
        subtitle =
            'SmartBet cerca alternative senza abbassare la quota minima.';
        break;
      default:
        title = 'Caricamento partite…';
        subtitle = 'Preparazione del palinsesto di oggi.';
    }

    final progress = _total > 0 ? (_processed / _total).clamp(0.0, 1.0) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(20),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF9FE0A5),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.35,
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
          'Risultati del Giorno SmartBet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 23,
                  height: 23,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Rigenera',
              onPressed: _generate,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _generate,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFF009688)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'TOP 3 DEL GIORNO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'SmartBet cerca le 3 selezioni più solide del giorno '
                    'tra i mercati supportati, con analisi SmartBet avanzata, Auditor '
                    'e quota bookmaker reale almeno 1.25.',
                    style: TextStyle(color: Colors.white, height: 1.35),
                  ),
                ],
              ),
            ),
            if (_loading) ...[const SizedBox(height: 16), _progressCard()],
            if (_error != null && _results.isEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.orangeAccent,
                      size: 38,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _loading ? null : _generate,
                      icon: const Icon(Icons.refresh),
                      label: const Text('RIPROVA'),
                    ),
                  ],
                ),
              ),
            ],
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    _loading
                        ? 'SELEZIONI PROVVISORIE • ${_results.length}/$_wantedResults'
                        : 'LE 3 SELEZIONI DI OGGI',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_loading) ...[
                const SizedBox(height: 5),
                const Text(
                  'La classifica può aggiornarsi fino al completamento.',
                  style: TextStyle(color: Colors.white38, fontSize: 10.5),
                ),
              ],
              const SizedBox(height: 12),
              ...List.generate(
                _results.length,
                (index) => _resultCard(_results[index], index + 1),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Analisi statistiche a scopo informativo. '
              'Le probabilità sono stime del modello e non garantiscono '
              'l’esito di una partita.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white30,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODELLI LOCALI
// ============================================================

class _PreCandidate {
  final MatchModel match;
  final AnalysisResult analysis;
  final int bestProbability;

  const _PreCandidate({
    required this.match,
    required this.analysis,
    required this.bestProbability,
  });
}

class _DailyPick {
  final MatchModel match;
  final AnalysisResult analysis;
  final String market;
  final int probability;
  final double odd;
  final String bookmaker;
  final double edge;
  final double expectedValue;
  final double rankScore;
  final String auditStatus;
  final _ExactScoreEstimate exactPrimary;
  final _ExactScoreEstimate exactAlternative;
  final _ExactScoreEstimate exactThird;

  const _DailyPick({
    required this.match,
    required this.analysis,
    required this.market,
    required this.probability,
    required this.odd,
    required this.bookmaker,
    required this.edge,
    required this.expectedValue,
    required this.rankScore,
    required this.auditStatus,
    required this.exactPrimary,
    required this.exactAlternative,
    required this.exactThird,
  });
}

class _ExactScoreEstimate {
  final int homeGoals;
  final int awayGoals;
  final double probability;

  const _ExactScoreEstimate({
    required this.homeGoals,
    required this.awayGoals,
    required this.probability,
  });

  String get label => '$homeGoals-$awayGoals';
}
