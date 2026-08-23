import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import '../services/italy_schedule_filter.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  bool _loading = false;

  String? _error;

  int _processed = 0;
  int _total = 0;

  final List<_DailyExactResult> _results = [];

  static const int _wantedResults = 3;
  static const int _maximumMatchesToAnalyze = 36;
  static const int _batchSize = 6;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generate();
    });
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

      setState(() {
        _total = selectedMatches.length;
      });

      if (selectedMatches.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Non ci sono partite disponibili nel Palinsesto Italia.';
        });

        return;
      }

      final candidates = <_DailyExactResult>[];

      for (var start = 0; start < selectedMatches.length; start += _batchSize) {
        final end = math.min(start + _batchSize, selectedMatches.length);

        final batch = selectedMatches.sublist(start, end);

        final analyzed = await Future.wait(
          batch.map((match) async {
            try {
              final analysis = await SmartCore.analyze(match);

              if (analysis.smartScore <= 0) {
                return null;
              }

              return _buildExactResult(match, analysis);
            } catch (_) {
              return null;
            }
          }),
        );

        candidates.addAll(analyzed.whereType<_DailyExactResult>());

        if (!mounted) {
          return;
        }

        setState(() {
          _processed = end;
        });
      }

      candidates.sort((a, b) => b.rankScore.compareTo(a.rankScore));

      if (!mounted) {
        return;
      }

      setState(() {
        _results
          ..clear()
          ..addAll(candidates.take(_wantedResults));

        _loading = false;

        if (_results.isEmpty) {
          _error =
              'SmartBet non ha trovato risultati esatti '
              'con affidabilità sufficiente.';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error =
            'Non è stato possibile generare i risultati del giorno. '
            'Riprova tra poco.';
      });
    }
  }

  // ============================================================
  // COSTRUZIONE RISULTATO ESATTO
  // ============================================================

  _DailyExactResult _buildExactResult(
    MatchModel match,
    AnalysisResult analysis,
  ) {
    final totalGoals = _estimateTotalGoals(analysis);

    final home = analysis.homeProbability.toDouble();
    final away = analysis.awayProbability.toDouble();
    final draw = analysis.drawProbability.toDouble();

    final homeAwayTotal = math.max(1.0, home + away);

    final rawHomeShare = home / homeAwayTotal;

    // Il pareggio riduce la separazione tra le due squadre.
    final decisiveness = (1.0 - draw / 100.0).clamp(0.45, 0.90).toDouble();

    var homeShare = 0.5 + (rawHomeShare - 0.5) * decisiveness;

    homeShare = homeShare.clamp(0.27, 0.73).toDouble();

    // Goal / No Goal ci aiuta a correggere la distribuzione
    // senza utilizzare quote bookmaker.
    if (analysis.goalProbability >= 62) {
      homeShare = homeShare.clamp(0.32, 0.68).toDouble();
    }

    if (analysis.noGoalProbability >= 65) {
      if (homeShare >= 0.5) {
        homeShare = math.min(0.76, homeShare + 0.04);
      } else {
        homeShare = math.max(0.24, homeShare - 0.04);
      }
    }

    final homeXg = totalGoals * homeShare;
    final awayXg = totalGoals - homeXg;

    final scoreOptions = <_ExactScore>[];

    for (var homeGoals = 0; homeGoals <= 5; homeGoals++) {
      for (var awayGoals = 0; awayGoals <= 5; awayGoals++) {
        var probability =
            _poisson(homeGoals, homeXg) * _poisson(awayGoals, awayXg);

        // Coerenza leggera con la distribuzione 1X2.
        if (homeGoals > awayGoals) {
          probability *= 0.80 + (analysis.homeProbability / 100.0) * 0.40;
        } else if (homeGoals == awayGoals) {
          probability *= 0.80 + (analysis.drawProbability / 100.0) * 0.40;
        } else {
          probability *= 0.80 + (analysis.awayProbability / 100.0) * 0.40;
        }

        scoreOptions.add(
          _ExactScore(
            homeGoals: homeGoals,
            awayGoals: awayGoals,
            probability: probability,
          ),
        );
      }
    }

    final probabilityTotal = scoreOptions.fold<double>(
      0.0,
      (sum, item) => sum + item.probability,
    );

    final normalized = scoreOptions
        .map(
          (item) => _ExactScore(
            homeGoals: item.homeGoals,
            awayGoals: item.awayGoals,
            probability: probabilityTotal > 0
                ? item.probability / probabilityTotal
                : 0.0,
          ),
        )
        .toList();

    normalized.sort((a, b) => b.probability.compareTo(a.probability));

    final primary = normalized.first;
    final alternative = normalized[1];

    final combinedExactProbability =
        primary.probability + alternative.probability;

    final bestMatchProbability = math.max(
      analysis.homeProbability,
      math.max(analysis.drawProbability, analysis.awayProbability),
    );

    // Ranking utilizzato esclusivamente per scegliere
    // le tre partite più "leggibili".
    final rankScore =
        combinedExactProbability * 100.0 * 0.55 +
        analysis.smartScore * 0.30 +
        bestMatchProbability * 0.15;

    return _DailyExactResult(
      match: match,
      analysis: analysis,
      homeExpectedGoals: homeXg,
      awayExpectedGoals: awayXg,
      primary: primary,
      alternative: alternative,
      rankScore: rankScore,
    );
  }

  // ============================================================
  // GOL ATTESI
  // ============================================================

  double _estimateTotalGoals(AnalysisResult analysis) {
    final estimates = <double>[];

    if (analysis.over25Probability > 0) {
      estimates.add(
        _lambdaFromOverProbability(
          analysis.over25Probability / 100.0,
          minimumGoals: 3,
        ),
      );
    }

    if (analysis.over15Probability > 0) {
      estimates.add(
        _lambdaFromOverProbability(
          analysis.over15Probability / 100.0,
          minimumGoals: 2,
        ),
      );
    }

    double total;

    if (estimates.isNotEmpty) {
      total = estimates.reduce((a, b) => a + b) / estimates.length;
    } else {
      // Fallback prudente.
      total = 2.45;

      if (analysis.goalProbability > 50) {
        total += (analysis.goalProbability - 50) / 100.0;
      }

      if (analysis.noGoalProbability > 60) {
        total -= 0.20;
      }
    }

    return total.clamp(1.20, 4.50).toDouble();
  }

  double _lambdaFromOverProbability(
    double probability, {
    required int minimumGoals,
  }) {
    final target = probability.clamp(0.05, 0.95).toDouble();

    var low = 0.25;
    var high = 6.0;

    for (var i = 0; i < 45; i++) {
      final mid = (low + high) / 2.0;

      final over = 1.0 - _poissonCumulative(minimumGoals - 1, mid);

      if (over < target) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return (low + high) / 2.0;
  }

  double _poissonCumulative(int maxGoals, double lambda) {
    var sum = 0.0;

    for (var goals = 0; goals <= maxGoals; goals++) {
      sum += _poisson(goals, lambda);
    }

    return sum;
  }

  double _poisson(int goals, double lambda) {
    var factorial = 1.0;

    for (var i = 2; i <= goals; i++) {
      factorial *= i;
    }

    return math.exp(-lambda) * math.pow(lambda, goals).toDouble() / factorial;
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

  String _confidenceLabel(_DailyExactResult result) {
    final combined =
        result.primary.probability + result.alternative.probability;

    if (result.analysis.smartScore >= 70 && combined >= 0.24) {
      return 'Alta';
    }

    if (result.analysis.smartScore >= 55 && combined >= 0.18) {
      return 'Buona';
    }

    return 'Prudente';
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _resultCard(_DailyExactResult item, int position) {
    final scoreColor = _scoreColor(item.analysis.smartScore);

    final competition = _competitionLabel(item.match);
    final time = _matchTime(item.match);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scoreColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$position',
                  style: const TextStyle(
                    color: Color(0xFF00C853),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  competition,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            '${item.match.homeTeam} - '
            '${item.match.awayTeam}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _exactScoreBox(
                  title: 'RISULTATO PRINCIPALE',
                  score: item.primary.label,
                  probability: item.primary.probability,
                  primary: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _exactScoreBox(
                  title: 'ALTERNATIVA',
                  score: item.alternative.label,
                  probability: item.alternative.probability,
                  primary: false,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _infoBox(
                  'Gol attesi',
                  '${item.homeExpectedGoals.toStringAsFixed(2)}'
                      ' - '
                      '${item.awayExpectedGoals.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _infoBox(
                  'Smart Score',
                  '${item.analysis.smartScore}',
                  valueColor: scoreColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _infoBox('Affidabilità', _confidenceLabel(item))),
            ],
          ),

          const SizedBox(height: 13),

          const Text(
            'I punteggi sono scenari statistici stimati '
            'da probabilità SmartBet e mercati gol. '
            'Le quote bookmaker non vengono utilizzate '
            'per generarli.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _exactScoreBox({
    required String title,
    required String score,
    required double probability,
    required bool primary,
  }) {
    final accent = primary ? const Color(0xFF00C853) : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            score,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${(probability * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
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
              fontSize: 12,
              fontWeight: FontWeight.bold,
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
          'Risultati del Giorno AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Rigenera',
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _results.isEmpty) {
      final progress = _total > 0 ? _processed / _total : null;

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: progress),
              const SizedBox(height: 20),
              const Text(
                'SmartBet sta cercando i 3 risultati '
                'più interessanti del giorno…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _total > 0
                    ? 'Analizzate $_processed / $_total partite'
                    : 'Caricamento Palinsesto Italia…',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.scoreboard_outlined,
                color: Color(0xFF00C853),
                size: 64,
              ),
              const SizedBox(height: 18),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.refresh),
                label: const Text('RIPROVA'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
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
                    Icon(Icons.scoreboard_outlined, color: Colors.white),
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
                  'SmartBet seleziona automaticamente '
                  '3 partite dal Palinsesto Italia e propone '
                  'due scenari di risultato esatto per ciascuna.',
                  style: TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          ...List.generate(
            _results.length,
            (index) => _resultCard(_results[index], index + 1),
          ),

          if (_loading) ...[
            const SizedBox(height: 8),
            const Center(child: CircularProgressIndicator()),
          ],

          const SizedBox(height: 6),

          const Text(
            'Previsioni statistiche a scopo informativo. '
            'I risultati esatti hanno naturalmente una '
            'probabilità inferiore rispetto ai mercati più ampi. '
            'Gioca responsabilmente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white30,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MODELLI LOCALI
// ============================================================

class _DailyExactResult {
  final MatchModel match;
  final AnalysisResult analysis;

  final double homeExpectedGoals;
  final double awayExpectedGoals;

  final _ExactScore primary;
  final _ExactScore alternative;

  final double rankScore;

  const _DailyExactResult({
    required this.match,
    required this.analysis,
    required this.homeExpectedGoals,
    required this.awayExpectedGoals,
    required this.primary,
    required this.alternative,
    required this.rankScore,
  });
}

class _ExactScore {
  final int homeGoals;
  final int awayGoals;
  final double probability;

  const _ExactScore({
    required this.homeGoals,
    required this.awayGoals,
    required this.probability,
  });

  String get label => '$homeGoals-$awayGoals';
}
