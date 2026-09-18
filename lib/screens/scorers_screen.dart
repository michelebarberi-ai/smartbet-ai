import 'package:flutter/material.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import '../services/italy_schedule_filter.dart';
import '../services/scorer_candidate_service.dart';

class ScorersScreen extends StatefulWidget {
  const ScorersScreen({super.key});

  @override
  State<ScorersScreen> createState() => _ScorersScreenState();
}

class _ScorersScreenState extends State<ScorersScreen> {
  static const int _wantedScorers = 5;
  static const int _maximumMatchesToPreAnalyze = 12;
  static const int _matchesForPlayerScan = 6;
  static const int _preBatchSize = 3;

  final ScorerCandidateService _service = ScorerCandidateService();

  final List<ScorerCandidate> _results = [];

  bool _loading = false;
  String? _error;
  String _phase = 'idle';
  int _processed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generate();
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  bool _isUpcoming(MatchModel match) {
    try {
      return DateTime.parse(match.date).toLocal().isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _formatTime(String raw) {
    try {
      final date = DateTime.parse(raw).toLocal();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  Future<void> _generate() async {
    if (_loading) return;

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

      final matches =
          allMatches
              .where(
                (match) =>
                    match.hasTeamIds &&
                    match.fixtureId > 0 &&
                    _isUpcoming(match) &&
                    ItalyScheduleFilter.allows(match),
              )
              .toList()
            ..sort((a, b) => b.aiWeight.compareTo(a.aiWeight));

      if (matches.isEmpty) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _phase = 'done';
          _error =
              'Non ci sono partite future idonee per la ricerca marcatori.';
        });
        return;
      }

      final scanMatches = matches.take(_maximumMatchesToPreAnalyze).toList();

      if (!mounted) return;

      setState(() {
        _phase = 'scan';
        _processed = 0;
        _total = scanMatches.length;
      });

      final prelim = <_ScorerMatchCandidate>[];

      for (var start = 0; start < scanMatches.length; start += _preBatchSize) {
        final end = (start + _preBatchSize).clamp(0, scanMatches.length);

        final batch = scanMatches.sublist(start, end);

        final analyzed = await Future.wait(
          batch.map((match) async {
            try {
              final analysis = await SmartCore.analyze(match);

              return _ScorerMatchCandidate(
                match: match,
                analysis: analysis,
                attackScore: _attackScore(analysis),
              );
            } catch (_) {
              return null;
            }
          }),
        );

        prelim.addAll(analyzed.whereType<_ScorerMatchCandidate>());

        if (!mounted) return;

        setState(() {
          _processed = end;
        });
      }

      if (prelim.isEmpty) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _phase = 'done';
          _error =
              'SmartBet non è riuscito a costruire la shortlist delle partite.';
        });
        return;
      }

      prelim.sort((a, b) {
        final scoreCompare = b.attackScore.compareTo(a.attackScore);

        if (scoreCompare != 0) {
          return scoreCompare;
        }

        return b.analysis.smartScore.compareTo(a.analysis.smartScore);
      });

      final playerMatches = prelim.take(_matchesForPlayerScan).toList();

      if (!mounted) return;

      setState(() {
        _phase = 'players';
        _processed = 0;
        _total = playerMatches.length;
      });

      final allCandidates = <ScorerCandidate>[];

      for (var i = 0; i < playerMatches.length; i++) {
        final item = playerMatches[i];

        try {
          final candidates = await _service.buildForMatch(
            match: item.match,
            analysis: item.analysis,
          );

          allCandidates.addAll(candidates);
        } catch (_) {
          // Una singola partita non deve fermare l'intera ricerca.
        }

        final snapshot = _selectFinalCandidates(allCandidates);

        if (!mounted) return;

        setState(() {
          _processed = i + 1;
          _results
            ..clear()
            ..addAll(snapshot);
        });
      }

      final finalResults = _selectFinalCandidates(allCandidates);

      if (!mounted) return;

      setState(() {
        _results
          ..clear()
          ..addAll(finalResults);

        _loading = false;
        _phase = 'done';

        if (_results.isEmpty) {
          _error =
              'Oggi SmartBet non ha trovato marcatori con dati '
              'sufficientemente solidi. Nessun nome viene forzato.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _phase = 'done';
        _error = _friendlyError(e);
      });
    }
  }

  double _attackScore(AnalysisResult analysis) {
    final expectedGoals =
        analysis.expectedHomeGoals + analysis.expectedAwayGoals;

    final xgScore = expectedGoals > 0 ? expectedGoals * 22.0 : 0.0;

    return xgScore +
        analysis.over25Probability * 0.50 +
        analysis.goalProbability * 0.25 +
        analysis.smartScore * 0.15;
  }

  List<ScorerCandidate> _selectFinalCandidates(List<ScorerCandidate> source) {
    final sorted = [...source]
      ..sort((a, b) => b.rankScore.compareTo(a.rankScore));

    final selected = <ScorerCandidate>[];
    final perFixture = <int, int>{};
    final seenPlayers = <int>{};

    for (final candidate in sorted) {
      if (seenPlayers.contains(candidate.playerId)) {
        continue;
      }

      final fixtureCount = perFixture[candidate.match.fixtureId] ?? 0;

      if (fixtureCount >= 2) {
        continue;
      }

      // Con formazione ufficiale disponibile non mostriamo un panchinaro
      // nella Top 5 finale.
      if (candidate.officialLineupKnown && !candidate.confirmedStarter) {
        continue;
      }

      selected.add(candidate);
      seenPlayers.add(candidate.playerId);
      perFixture[candidate.match.fixtureId] = fixtureCount + 1;

      if (selected.length >= _wantedScorers) {
        break;
      }
    }

    return selected;
  }

  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('socket') ||
        raw.contains('host lookup') ||
        raw.contains('network')) {
      return 'Impossibile collegarsi ai servizi SmartBet. '
          'Controlla la connessione e riprova.';
    }

    if (raw.contains('timeout')) {
      return 'I servizi stanno impiegando troppo tempo a rispondere. '
          'Riprova tra poco.';
    }

    return 'Non è stato possibile completare la ricerca dei marcatori.';
  }

  String get _progressTitle {
    switch (_phase) {
      case 'matches':
        return 'Caricamento partite di oggi…';
      case 'scan':
        return 'Scansione partite: $_processed / $_total';
      case 'players':
        return 'Analisi giocatori: $_processed / $_total';
      default:
        return 'SmartBet sta lavorando…';
    }
  }

  String get _progressSubtitle {
    switch (_phase) {
      case 'scan':
        return 'SmartBet individua le partite con il miglior potenziale offensivo.';
      case 'players':
        return 'Gol, minuti, titolarità, tiri, assenze e formazioni vengono incrociati.';
      default:
        return 'Preparazione della shortlist marcatori.';
    }
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
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
              Icon(Icons.sports_soccer, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'MARCATORI DEL GIORNO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 11),
          Text(
            'SmartBet cerca fino a 5 giocatori con il profilo più '
            'interessante nelle partite di oggi. Nessun marcatore '
            'viene inserito solo per raggiungere il numero richiesto.',
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    final value = _total > 0
        ? (_processed / _total).clamp(0.0, 1.0).toDouble()
        : null;

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: value,
            minHeight: 7,
            borderRadius: BorderRadius.circular(20),
          ),
          const SizedBox(height: 14),
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
                  _progressTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _progressSubtitle,
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

  Widget _metric({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidateCard(ScorerCandidate item, int position) {
    final time = _formatTime(item.match.date);

    final competition = [
      item.match.country,
      item.match.league,
    ].where((value) => value.trim().isNotEmpty).join(' • ');

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00C853).withValues(alpha: 0.34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$position',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  competition,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            item.playerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.teamName,
            style: const TextStyle(
              color: Color(0xFF9FE0A5),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${item.match.homeTeam} - ${item.match.awayTeam}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'PROBABILITÀ SMARTBET',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${(item.probability * 100).round()}%',
                        style: const TextStyle(
                          color: Color(0xFF00C853),
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '2+ GOL  ${(item.braceProbability * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'DISPONIBILITÀ',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        item.availabilityLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: item.confirmedStarter
                              ? const Color(0xFF00C853)
                              : Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (item.odd != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sell_outlined,
                    color: Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '@ ${item.odd!.odd.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.odd!.bookmaker,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              _metric(label: 'Gol', value: '${item.seasonGoals}'),
              const SizedBox(width: 7),
              _metric(
                label: 'Gol / 90',
                value: item.goalsPer90.toStringAsFixed(2),
              ),
              const SizedBox(width: 7),
              _metric(
                label: 'Tiri porta / 90',
                value: item.shotsOnTargetPer90.toStringAsFixed(2),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Icon(
                Icons.insights_outlined,
                color: Colors.white38,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Potenziale squadra: '
                  '${item.teamExpectedGoals.toStringAsFixed(2)} gol attesi • '
                  '${item.appearances} presenze',
                  style: const TextStyle(
                    color: Color(0x73FFFFFF),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyOrError() {
    if (_error == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 34),
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.refresh),
            label: const Text('RIPROVA'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Possibili Marcatori SmartBet',
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          _hero(),
          if (_loading) _progressCard(),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              _loading
                  ? 'MARCATORI PROVVISORI • ${_results.length}/$_wantedScorers'
                  : 'I MIGLIORI ${_results.length} DI OGGI',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 5),
              const Text(
                'La classifica può aggiornarsi mentre SmartBet continua l’analisi.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
            ...List.generate(
              _results.length,
              (index) => _candidateCard(_results[index], index + 1),
            ),
          ],
          if (!_loading) _emptyOrError(),
          const SizedBox(height: 18),
          const Text(
            'Stime statistiche a scopo informativo. La probabilità di segnare '
            'dipende anche da titolarità, minuti effettivi e dinamica della partita.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ScorerMatchCandidate {
  final MatchModel match;
  final AnalysisResult analysis;
  final double attackScore;

  const _ScorerMatchCandidate({
    required this.match,
    required this.analysis,
    required this.attackScore,
  });
}
