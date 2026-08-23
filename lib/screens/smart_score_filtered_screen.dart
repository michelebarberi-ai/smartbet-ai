import 'package:flutter/material.dart';

import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import '../services/smartbet_ai_service.dart';
import 'analysis_detail_screen.dart';

class SmartScoreFilteredScreen extends StatefulWidget {
  final DateTime selectedDate;
  final int minimumSmartScore;

  const SmartScoreFilteredScreen({
    super.key,
    required this.selectedDate,
    required this.minimumSmartScore,
  });

  @override
  State<SmartScoreFilteredScreen> createState() =>
      _SmartScoreFilteredScreenState();
}

class _FilteredMatch {
  final MatchModel match;
  final AnalysisResult analysis;

  const _FilteredMatch({required this.match, required this.analysis});
}

class _SmartScoreFilteredScreenState extends State<SmartScoreFilteredScreen> {
  final List<_FilteredMatch> _results = [];

  String _searchText = '';

  bool _loading = true;
  String? _errorMessage;

  int _processed = 0;
  int _total = 0;
  int _analysisErrors = 0;

  static const int _batchSize = 3;

  @override
  void initState() {
    super.initState();
    _scanMatches();
  }

  // ============================================================
  // DATA
  // ============================================================

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<List<MatchModel>> _loadMatchesForDate() {
    final today = _dateOnly(DateTime.now());
    final selected = _dateOnly(widget.selectedDate);

    if (_isSameDate(today, selected)) {
      return MatchRepository.getTodayMatches();
    }

    return MatchRepository.getMatchesByDate(selected);
  }

  // ============================================================
  // SCANSIONE COMPLETA
  // ============================================================

  Future<void> _scanMatches() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
        _processed = 0;
        _total = 0;
        _analysisErrors = 0;
        _results.clear();
      });
    }

    try {
      final matches = await _loadMatchesForDate();

      if (!mounted) {
        return;
      }

      setState(() {
        _total = matches.length;
      });

      for (var start = 0; start < matches.length; start += _batchSize) {
        if (!mounted) {
          return;
        }

        final end = (start + _batchSize).clamp(0, matches.length);
        final batch = matches.sublist(start, end);

        final analyzedBatch = await Future.wait(
          batch.map((match) async {
            try {
              final analysis = await SmartCore.analyze(match);

              return _FilteredMatch(match: match, analysis: analysis);
            } catch (_) {
              return null;
            }
          }),
        );

        var batchErrors = 0;

        for (final item in analyzedBatch) {
          if (item == null) {
            batchErrors++;
            continue;
          }

          if (item.analysis.smartScore >= widget.minimumSmartScore) {
            _results.add(item);
          }
        }

        _results.sort(
          (a, b) => b.analysis.smartScore.compareTo(a.analysis.smartScore),
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _processed = end;
          _analysisErrors += batchErrors;
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
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
      return 'Il servizio sta impiegando troppo tempo a rispondere. '
          'Riprova tra qualche istante.';
    }

    if (raw.contains('429') ||
        raw.contains('too many requests') ||
        raw.contains('rate limit')) {
      return 'Il servizio dati è temporaneamente occupato. '
          'Attendi qualche istante e riprova.';
    }

    return 'Si è verificato un problema durante il recupero dei dati. '
        'Riprova tra poco.';
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

      final day = parsed.day.toString().padLeft(2, '0');
      final month = parsed.month.toString().padLeft(2, '0');
      final hour = parsed.hour.toString().padLeft(2, '0');
      final minute = parsed.minute.toString().padLeft(2, '0');

      return '$day/$month $hour:$minute';
    } catch (_) {
      return date;
    }
  }

  String _selectedDateLabel() {
    final day = widget.selectedDate.day.toString().padLeft(2, '0');
    final month = widget.selectedDate.month.toString().padLeft(2, '0');
    final year = widget.selectedDate.year;

    return '$day/$month/$year';
  }

  Color _scoreColor(int score) {
    if (score >= 80) {
      return Colors.green;
    }

    if (score >= 65) {
      return Colors.orange;
    }

    return Colors.redAccent;
  }

  bool _matchesSearch(_FilteredMatch item) {
    final search = _searchText.trim().toLowerCase();

    if (search.isEmpty) {
      return true;
    }

    final match = item.match;

    return match.homeTeam.toLowerCase().contains(search) ||
        match.awayTeam.toLowerCase().contains(search) ||
        match.league.toLowerCase().contains(search) ||
        match.country.toLowerCase().contains(search);
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
  // PROBABILITY BOX
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
            '$probability%',
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
  // CARD RISULTATO
  // ============================================================

  Widget _resultCard(_FilteredMatch item) {
    final match = item.match;
    final result = item.analysis;
    final scoreColor = _scoreColor(result.smartScore);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1F2937),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: scoreColor.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${match.country} • ${match.league}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  _formatDate(match.date),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),

            const SizedBox(height: 11),

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
                    'VS',
                    style: TextStyle(
                      color: Colors.white30,
                      fontSize: 10,
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

            const SizedBox(height: 14),

            Row(
              children: [
                Icon(Icons.psychology, color: scoreColor, size: 22),
                const SizedBox(width: 7),
                Text(
                  'Smart Score ${result.smartScore}',
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                const Text(
                  'PRE-ANALISI',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  result.prediction,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 9),

            LinearProgressIndicator(
              value: result.smartScore.clamp(0, 100) / 100,
              minHeight: 7,
              borderRadius: BorderRadius.circular(20),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
            ),

            const SizedBox(height: 13),

            Row(
              children: [
                Expanded(child: _probabilityBox('1', result.homeProbability)),
                const SizedBox(width: 7),
                Expanded(child: _probabilityBox('X', result.drawProbability)),
                const SizedBox(width: 7),
                Expanded(child: _probabilityBox('2', result.awayProbability)),
              ],
            ),

            const SizedBox(height: 13),

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
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _header() {
    final veryReliable = widget.minimumSmartScore >= 75;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF172033),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                veryReliable ? Icons.verified : Icons.filter_alt,
                color: const Color(0xFF00C853),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  veryReliable ? 'Molto affidabili' : 'Partite affidabili',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C853).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '≥ ${widget.minimumSmartScore}',
                  style: const TextStyle(
                    color: Color(0xFF00C853),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            '${_selectedDateLabel()} • '
            '${_results.length} trovate',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.4,
            ),
          ),

          if (_loading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _total > 0 ? (_processed / _total).clamp(0.0, 1.0) : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(height: 6),
            Text(
              _total > 0
                  ? 'Verifica $_processed / $_total partite...'
                  : 'Caricamento partite...',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],

          if (!_loading && _analysisErrors > 0) ...[
            const SizedBox(height: 6),
            Text(
              '$_analysisErrors partite non sono state analizzate '
              'per dati insufficienti o errore temporaneo.',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ],

          const SizedBox(height: 14),

          TextField(
            onChanged: (value) {
              setState(() {
                _searchText = value;
              });
            },
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Cerca tra le partite filtrate...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
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
    final visibleResults = _results.where(_matchesSearch).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: Text(
          'Smart Score ≥${widget.minimumSmartScore}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          _header(),

          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: Colors.orangeAccent,
                            size: 58,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _scanMatches,
                            icon: const Icon(Icons.refresh),
                            label: const Text('RIPROVA'),
                          ),
                        ],
                      ),
                    ),
                  )
                : visibleResults.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _loading
                                ? Icons.manage_search
                                : Icons.filter_alt_off,
                            color: _loading
                                ? const Color(0xFF00C853)
                                : Colors.white30,
                            size: 54,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _loading
                                ? 'Sto cercando le partite '
                                      'con Smart Score '
                                      '≥${widget.minimumSmartScore}...'
                                : 'Nessuna partita con '
                                      'Smart Score '
                                      '≥${widget.minimumSmartScore} '
                                      'trovata per questa data.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                          if (!_loading) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _scanMatches,
                              icon: const Icon(Icons.refresh),
                              label: const Text('RIPETI VERIFICA'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                    itemCount: visibleResults.length,
                    itemBuilder: (context, index) {
                      return _resultCard(visibleResults[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
