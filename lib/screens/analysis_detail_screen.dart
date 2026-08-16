import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../services/bankroll_store.dart';
import '../services/bet_execution_service.dart';

class AnalysisDetailScreen extends StatefulWidget {
  final MatchModel match;
  final AnalysisResult result;

  const AnalysisDetailScreen({
    super.key,
    required this.match,
    required this.result,
  });

  @override
  State<AnalysisDetailScreen> createState() => _AnalysisDetailScreenState();
}

class _AnalysisDetailScreenState extends State<AnalysisDetailScreen> {
  final BankrollStore _bankroll = BankrollStore.instance;

  bool _registering = false;

  // ============================================================
  // MATCH LABEL
  // ============================================================

  String get _matchLabel {
    return '${widget.match.homeTeam} - ${widget.match.awayTeam}';
  }

  // ============================================================
  // PREVIEW BET
  // ============================================================

  BetExecutionPreview get _preview {
    final execution = BetExecutionService(bankrollManager: _bankroll.manager);

    return execution.preview(analysis: widget.result);
  }

  // ============================================================
  // REGISTRA BET
  // ============================================================

  Future<void> _registerBet() async {
    if (_registering) {
      return;
    }

    final preview = _preview;

    if (!preview.canPlaceBet) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(preview.message)));

      return;
    }

    setState(() {
      _registering = true;
    });

    final bet = await _bankroll.placeBet(
      matchLabel: _matchLabel,
      outcome: preview.outcome,
      odd: preview.odd,
      bookmaker: preview.bookmaker,
      stakePercent: preview.stakePercent,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _registering = false;
    });

    if (bet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile registrare la puntata.')),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Puntata registrata: '
          '€${bet.stakeAmount.toStringAsFixed(2)} '
          'su ${bet.outcome} '
          '@ ${bet.odd.toStringAsFixed(2)}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final result = widget.result;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Analisi SmartBet'),
      ),
      body: AnimatedBuilder(
        animation: _bankroll,
        builder: (context, child) {
          final preview = _preview;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              // =================================================
              // MATCH
              // =================================================
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      '${match.homeTeam} - ${match.awayTeam}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      match.league,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // =================================================
              // PRONOSTICO
              // =================================================
              _sectionCard(
                title: 'PRONOSTICO',
                child: Column(
                  children: [
                    Text(
                      result.prediction,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _probabilityBox('1', result.homeProbability),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _probabilityBox('X', result.drawProbability),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _probabilityBox('2', result.awayProbability),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // QUOTE GOL
              // =================================================
              _sectionCard(
                title: 'QUOTE GOL',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.sports_soccer,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'OVER / UNDER 2.5',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _probabilityBox(
                            'OVER 2.5',
                            result.over25Probability,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _probabilityBox(
                            'UNDER 2.5',
                            result.under25Probability,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    const Divider(color: Colors.white12, height: 1),

                    const SizedBox(height: 20),

                    const Row(
                      children: [
                        Icon(
                          Icons.compare_arrows,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'GOAL / NO GOAL',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _probabilityBox(
                            'GOAL',
                            result.goalProbability,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _probabilityBox(
                            'NO GOAL',
                            result.noGoalProbability,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    const Text(
                      'Probabilità stimate da SmartBet AI',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // SMART SCORE
              // =================================================
              _sectionCard(
                title: 'SMART SCORE',
                child: Row(
                  children: [
                    Text(
                      '${result.smartScore}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Valutazione complessiva SmartBet AI',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // VALUE BET
              // =================================================
              _sectionCard(
                title: 'VALUE BET',
                child: Text(
                  result.valueBet,
                  style: TextStyle(
                    color: result.shouldBet
                        ? Colors.greenAccent
                        : Colors.white70,
                    fontSize: 16,
                    fontWeight: result.shouldBet
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // RISCHIO
              // =================================================
              _sectionCard(
                title: 'RISCHIO',
                child: Text(
                  result.risk,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // =================================================
              // ANALISI AI STRUTTURATA
              // =================================================
              _buildAiAnalysis(result.explanation),

              const SizedBox(height: 24),

              // =================================================
              // BET EXECUTION
              // =================================================
              _betExecutionCard(preview),

              const SizedBox(height: 30),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // ANALISI AI STRUTTURATA
  // ============================================================

  Widget _buildAiAnalysis(String explanation) {
    final sections = _parseAiSections(explanation);

    final widgets = <Widget>[];

    void addSection(
      String key,
      String title, {
      IconData? icon,
      Color? accentColor,
      bool list = false,
    }) {
      final content = sections[key]?.trim() ?? '';

      if (content.isEmpty) {
        return;
      }

      widgets.add(
        _analysisSectionCard(
          title: title,
          content: content,
          icon: icon,
          accentColor: accentColor,
          list: list,
        ),
      );

      widgets.add(const SizedBox(height: 16));
    }

    addSection('SINTESI', 'SINTESI', icon: Icons.summarize_outlined);

    addSection(
      'ANALISI STATISTICA',
      'ANALISI STATISTICA',
      icon: Icons.query_stats,
    );

    addSection(
      'ANALISI NOTIZIE',
      'ANALISI NOTIZIE',
      icon: Icons.newspaper_outlined,
    );

    addSection(
      'FATTORI POSITIVI',
      'FATTORI POSITIVI',
      icon: Icons.trending_up,
      accentColor: Colors.greenAccent,
      list: true,
    );

    addSection(
      'FATTORI NEGATIVI',
      'FATTORI NEGATIVI',
      icon: Icons.warning_amber_rounded,
      accentColor: Colors.orangeAccent,
      list: true,
    );

    addSection(
      'ASSENZE',
      'ASSENZE',
      icon: Icons.person_off_outlined,
      accentColor: Colors.orangeAccent,
      list: true,
    );

    addSection(
      'VERDETTO FINALE AI',
      'VERDETTO FINALE AI',
      icon: Icons.psychology_alt_outlined,
      accentColor: Colors.greenAccent,
    );

    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }

    if (widgets.isEmpty) {
      return _sectionCard(
        title: 'ANALISI AI',
        child: Text(
          _cleanAiText(explanation),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      );
    }

    return Column(children: widgets);
  }

  // ============================================================
  // PARSER ANALISI
  // ============================================================

  Map<String, String> _parseAiSections(String explanation) {
    const knownSections = <String>{
      'SINTESI',
      'ANALISI STATISTICA',
      'ANALISI NOTIZIE',
      'FATTORI POSITIVI',
      'FATTORI NEGATIVI',
      'ASSENZE',
      'BEST ODDS / VALUE BET',
      'STAKE ENGINE',
      'VERDETTO FINALE AI',
    };

    final result = <String, String>{};

    String? currentSection;

    final buffer = StringBuffer();

    void saveCurrent() {
      if (currentSection == null) {
        buffer.clear();
        return;
      }

      final cleaned = _cleanAiText(buffer.toString()).trim();

      if (cleaned.isNotEmpty) {
        result[currentSection!] = cleaned;
      }

      buffer.clear();
    }

    for (final rawLine in explanation.split('\n')) {
      final line = rawLine.trim();

      if (line.isEmpty) {
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }

        continue;
      }

      if (RegExp(r'^-{5,}$').hasMatch(line)) {
        continue;
      }

      // Questi dati sono già mostrati
      // nella parte superiore della UI.
      if (line == 'SMARTBET AI' ||
          line.startsWith('PRONOSTICO:') ||
          line.startsWith('PROBABILITÀ:') ||
          line.startsWith('1: ') ||
          line.startsWith('X: ') ||
          line.startsWith('2: ') ||
          line.startsWith('CONFIDENCE AI:') ||
          line.startsWith('CONFIDENCE DOSSIER:') ||
          line == 'RISCHIO:' ||
          line == 'Basso' ||
          line == 'Medio' ||
          line == 'Alto' ||
          line == 'Medio-Basso' ||
          line == 'Medio-Alto') {
        continue;
      }

      if (knownSections.contains(line)) {
        saveCurrent();

        currentSection = line;

        continue;
      }

      if (currentSection != null) {
        buffer.writeln(line);
      }
    }

    saveCurrent();

    // Queste due sezioni hanno già
    // card specifiche nella UI.
    result.remove('BEST ODDS / VALUE BET');

    result.remove('STAKE ENGINE');

    return result;
  }

  // ============================================================
  // PULIZIA TESTO AI
  // ============================================================

  String _cleanAiText(String text) {
    var cleaned = text;

    // ==========================================================
    // LINK MARKDOWN
    // ==========================================================

    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(https?://[^\s)]+\)'),
      (match) => match.group(1) ?? '',
    );

    // ==========================================================
    // URL RESIDUI
    // ==========================================================

    cleaned = cleaned.replaceAll(RegExp(r'https?://\S+'), '');

    // ==========================================================
    // UTM
    // ==========================================================

    cleaned = cleaned.replaceAll(RegExp(r'\??utm_source=openai\)?'), '');

    // ==========================================================
    // PARENTESI VUOTE
    // ==========================================================

    cleaned = cleaned.replaceAll(RegExp(r'\(\s*\)'), '');

    // ==========================================================
    // SEPARATORI
    // ==========================================================

    cleaned = cleaned.replaceAll(RegExp(r'^-{5,}$', multiLine: true), '');

    // ==========================================================
    // RIGHE VUOTE MULTIPLE
    // ==========================================================

    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim();
  }

  // ============================================================
  // CARD ANALISI
  // ============================================================

  Widget _analysisSectionCard({
    required String title,
    required String content,
    IconData? icon,
    Color? accentColor,
    bool list = false,
  }) {
    final accent = accentColor ?? Colors.white54;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accentColor ?? Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (list)
            ..._buildAnalysisList(content, accent)
          else
            Text(
              content,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.55,
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // LISTE ANALISI
  // ============================================================

  List<Widget> _buildAnalysisList(String content, Color accent) {
    var items = content
        .split(RegExp(r'\n+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    // ==========================================================
    // SE TUTTO È SU UNA RIGA, PROVIAMO I BULLET
    // ==========================================================

    if (items.length == 1) {
      items = content
          .split(RegExp(r'\s*•\s*'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    // ==========================================================
    // NORMALIZZAZIONE
    // ==========================================================

    items = items
        .map((item) => item.replaceFirst(RegExp(r'^[•\-\*]\s*'), ''))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    // ==========================================================
    // RIMOZIONE DUPLICATI
    // ==========================================================

    final uniqueItems = <String>[];

    final seen = <String>{};

    for (final item in items) {
      final normalized = item.toLowerCase().trim();

      if (seen.add(normalized)) {
        uniqueItems.add(item);
      }
    }

    // ==========================================================
    // CASO "NON DISPONIBILE"
    // ==========================================================

    final hasUnavailable = uniqueItems.any((item) {
      final normalized = item.toLowerCase().trim();

      return normalized == 'non disponibile' ||
          normalized == 'non disponibile.';
    });

    if (hasUnavailable) {
      uniqueItems.removeWhere((item) {
        final normalized = item.toLowerCase().trim();

        return normalized == 'non disponibile' ||
            normalized == 'non disponibile.';
      });

      uniqueItems.insert(
        0,
        'Dati aggiornati su infortuni e squalifiche non disponibili.',
      );
    }

    // ==========================================================
    // WIDGET
    // ==========================================================

    return uniqueItems.map((item) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                item,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ============================================================
  // BET EXECUTION CARD
  // ============================================================

  Widget _betExecutionCard(BetExecutionPreview preview) {
    final snapshot = _bankroll.snapshot;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: preview.canPlaceBet
              ? Colors.green.withValues(alpha: 0.45)
              : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: preview.canPlaceBet
                    ? Colors.greenAccent
                    : Colors.white54,
              ),

              const SizedBox(width: 10),

              const Text(
                'SMARTBET BET',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (!preview.canPlaceBet)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                preview.message,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            )
          else ...[
            _betRow('Esito', preview.outcome),

            _betRow('Quota', preview.odd.toStringAsFixed(2)),

            _betRow('Bookmaker', preview.bookmaker),

            const Divider(color: Colors.white12, height: 28),

            _betRow(
              'Stake consigliato',
              '${preview.stakePercent.toStringAsFixed(2)}%',
            ),

            _betRow(
              'Importo',
              '€${preview.stakeAmount.toStringAsFixed(2)}',
              valueColor: Colors.greenAccent,
              bold: true,
            ),

            const Divider(color: Colors.white12, height: 28),

            _betRow(
              'Bankroll',
              '€${snapshot.currentBankroll.toStringAsFixed(2)}',
            ),

            _betRow(
              'Già impegnato',
              '€${snapshot.lockedBankroll.toStringAsFixed(2)}',
              valueColor: Colors.orange,
            ),

            _betRow(
              'Disponibile',
              '€${snapshot.availableBankroll.toStringAsFixed(2)}',
              valueColor: Colors.greenAccent,
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _registering ? null : _registerBet,
                icon: _registering
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _registering ? 'REGISTRAZIONE...' : 'REGISTRA PUNTATA',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.green.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // SECTION CARD
  // ============================================================

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),

          const SizedBox(height: 12),

          child,
        ],
      ),
    );
  }

  // ============================================================
  // PROBABILITY BOX
  // ============================================================

  Widget _probabilityBox(String label, num probability) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            '${probability.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BET ROW
  // ============================================================

  Widget _betRow(
    String label,
    String value, {
    Color valueColor = Colors.white,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white60)),
          ),

          const SizedBox(width: 12),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
