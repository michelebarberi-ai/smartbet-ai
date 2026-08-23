import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../services/bankroll_store.dart';
import '../services/bet_execution_service.dart';
import '../services/odds_service.dart';

class _RegisterMarketOption {
  final String label;
  final num probability;

  const _RegisterMarketOption(this.label, this.probability);
}

class _RegisterBetSheet extends StatefulWidget {
  final BankrollStore bankroll;
  final String matchLabel;
  final BetExecutionPreview preview;
  final AnalysisResult result;
  final List<_RegisterMarketOption> markets;
  final int fixtureId;

  const _RegisterBetSheet({
    required this.bankroll,
    required this.matchLabel,
    required this.preview,
    required this.result,
    required this.markets,
    required this.fixtureId,
  });

  @override
  State<_RegisterBetSheet> createState() => _RegisterBetSheetState();
}

class _RegisterBetSheetState extends State<_RegisterBetSheet> {
  late String _selectedOutcome;
  late final TextEditingController _oddController;
  late final TextEditingController _bookmakerController;
  late final TextEditingController _amountController;

  final OddsService _oddsService = OddsService();

  FixtureMarketOdds? _marketOdds;
  String? _errorMessage;
  bool _saving = false;
  bool _loadingOdds = true;

  @override
  void initState() {
    super.initState();

    _selectedOutcome = widget.preview.outcome.trim().isNotEmpty
        ? widget.preview.outcome.trim()
        : widget.result.prediction.trim();

    if (!widget.markets.any((item) => item.label == _selectedOutcome)) {
      _selectedOutcome = widget.result.prediction.trim();
    }

    _oddController = TextEditingController(
      text: widget.preview.odd > 1.0
          ? widget.preview.odd.toStringAsFixed(2)
          : '',
    );

    _bookmakerController = TextEditingController(
      text: widget.preview.bookmaker,
    );

    _amountController = TextEditingController(
      text: widget.preview.stakeAmount > 0.0
          ? widget.preview.stakeAmount.toStringAsFixed(2)
          : '',
    );

    _loadAutomaticOdds();
  }

  Future<void> _loadAutomaticOdds() async {
    final fixtureId = widget.fixtureId;

    if (fixtureId <= 0) {
      if (mounted) {
        setState(() {
          _loadingOdds = false;
        });
      }
      return;
    }

    final odds = await _oddsService.getFixtureMarketOdds(fixtureId: fixtureId);

    if (!mounted) {
      return;
    }

    setState(() {
      _marketOdds = odds;
      _loadingOdds = false;
    });

    _applyAutomaticOdd(_selectedOutcome);
  }

  void _applyAutomaticOdd(String outcome) {
    final best = _marketOdds?.oddFor(outcome);

    if (best == null) {
      // Manteniamo la quota SmartBet se coincide con quella consigliata.
      if (outcome == widget.preview.outcome && widget.preview.odd > 1.0) {
        _oddController.text = widget.preview.odd.toStringAsFixed(2);
        _bookmakerController.text = widget.preview.bookmaker;
      } else {
        _oddController.clear();
        _bookmakerController.clear();
      }
      return;
    }

    _oddController.text = best.odd.toStringAsFixed(2);
    _bookmakerController.text = best.bookmakerName;
  }

  @override
  void dispose() {
    _oddController.dispose();
    _bookmakerController.dispose();
    _amountController.dispose();
    _oddsService.dispose();
    super.dispose();
  }

  _RegisterMarketOption get _selected {
    return widget.markets.firstWhere((item) => item.label == _selectedOutcome);
  }

  Future<void> _confirm() async {
    if (_saving) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _errorMessage = null;
    });

    final odd = double.tryParse(
      _oddController.text.trim().replaceAll(',', '.'),
    );

    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );

    if (odd == null || odd <= 1.0) {
      setState(() {
        _errorMessage = 'Inserisci una quota valida superiore a 1.00.';
      });
      return;
    }

    if (amount == null || amount <= 0.0) {
      setState(() {
        _errorMessage = 'Inserisci un importo valido.';
      });
      return;
    }

    if (amount > widget.bankroll.availableBankroll) {
      setState(() {
        _errorMessage = 'L’importo supera il capitale disponibile.';
      });
      return;
    }

    if (widget.bankroll.hasBet(
      matchLabel: widget.matchLabel,
      outcome: _selectedOutcome,
      odd: odd,
    )) {
      setState(() {
        _errorMessage = 'Questa giocata risulta già registrata.';
      });
      return;
    }

    final stakePercent = widget.bankroll.currentBankroll > 0.0
        ? amount / widget.bankroll.currentBankroll * 100.0
        : 0.0;

    setState(() {
      _saving = true;
    });

    final bet = await widget.bankroll.placeBet(
      matchLabel: widget.matchLabel,
      outcome: _selectedOutcome,
      odd: odd,
      bookmaker: _bookmakerController.text.trim().isEmpty
          ? 'Non indicato'
          : _bookmakerController.text.trim(),
      stakePercent: stakePercent,
    );

    if (!mounted) {
      return;
    }

    if (bet == null) {
      setState(() {
        _saving = false;
        _errorMessage =
            'Impossibile registrare la giocata. Controlla i dati inseriti.';
      });
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bankroll = widget.bankroll.snapshot;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'REGISTRA LA TUA GIOCATA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.matchLabel,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scegli cosa hai effettivamente giocato',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.markets.map((item) {
                final active = item.label == _selectedOutcome;

                return ChoiceChip(
                  selected: active,
                  onSelected: (_) {
                    setState(() {
                      _errorMessage = null;
                      _selectedOutcome = item.label;

                      _applyAutomaticOdd(item.label);
                    });
                  },
                  label: Text(
                    '${item.label}  ${item.probability.toStringAsFixed(0)}%',
                  ),
                  labelStyle: TextStyle(
                    color: active ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  selectedColor: Colors.green.withValues(alpha: 0.35),
                  backgroundColor: const Color(0xFF1F2937),
                  side: BorderSide(
                    color: active ? Colors.greenAccent : Colors.white12,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Probabilità SmartBet: ${_selected.probability.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_loadingOdds)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    _marketOdds?.oddFor(_selectedOutcome) != null
                        ? Icons.auto_awesome
                        : Icons.edit_outlined,
                    size: 17,
                    color: _marketOdds?.oddFor(_selectedOutcome) != null
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                  ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _loadingOdds
                        ? 'Ricerca quota automatica...'
                        : _marketOdds?.oddFor(_selectedOutcome) != null
                        ? 'Migliore quota trovata automaticamente'
                        : 'Quota automatica non disponibile: puoi inserirla manualmente',
                    style: TextStyle(
                      color: _marketOdds?.oddFor(_selectedOutcome) != null
                          ? Colors.greenAccent
                          : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _oddController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Quota effettivamente giocata',
                labelStyle: TextStyle(color: Colors.white54),
                prefixIcon: Icon(Icons.trending_up, color: Colors.amber),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bookmakerController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Bookmaker',
                labelStyle: TextStyle(color: Colors.white54),
                prefixIcon: Icon(
                  Icons.account_balance_outlined,
                  color: Colors.white54,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Importo effettivamente giocato',
                labelStyle: const TextStyle(color: Colors.white54),
                prefixText: '€ ',
                prefixStyle: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
                helperText:
                    'Disponibile: €${bankroll.availableBankroll.toStringAsFixed(2)}',
                helperStyle: const TextStyle(color: Colors.white38),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white12),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Text(
                'SmartBet propone il pronostico, ma nello storico '
                'viene registrato ciò che hai effettivamente giocato.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _confirm,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _saving ? 'REGISTRAZIONE...' : 'CONFERMA REGISTRAZIONE',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

  final bool _registering = false;

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
  // REGISTRA GIOCATA PERSONALIZZATA
  // ============================================================

  List<_RegisterMarketOption> get _registerMarkets {
    final result = widget.result;

    return [
      _RegisterMarketOption('1', result.homeProbability),
      _RegisterMarketOption('X', result.drawProbability),
      _RegisterMarketOption('2', result.awayProbability),
      _RegisterMarketOption(
        '1X',
        result.homeProbability + result.drawProbability,
      ),
      _RegisterMarketOption(
        'X2',
        result.drawProbability + result.awayProbability,
      ),
      _RegisterMarketOption(
        '12',
        result.homeProbability + result.awayProbability,
      ),
      _RegisterMarketOption('OVER 1.5', result.over15Probability),
      _RegisterMarketOption('UNDER 1.5', result.under15Probability),
      _RegisterMarketOption('OVER 2.5', result.over25Probability),
      _RegisterMarketOption('UNDER 2.5', result.under25Probability),
      _RegisterMarketOption('GOAL', result.goalProbability),
      _RegisterMarketOption('NO GOAL', result.noGoalProbability),
    ];
  }

  Future<void> _openRegisterBetDialog(BetExecutionPreview preview) async {
    if (_registering) {
      return;
    }

    final registered = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return _RegisterBetSheet(
          bankroll: _bankroll,
          matchLabel: _matchLabel,
          preview: preview,
          result: widget.result,
          markets: _registerMarkets,
          fixtureId: widget.match.fixtureId,
        );
      },
    );

    if (registered == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Giocata registrata correttamente.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ============================================================
  // CONDIVIDI GIOCATA
  // ============================================================

  Future<void> _shareBet(BetExecutionPreview preview) async {
    if (!preview.canPlaceBet) {
      return;
    }

    final result = widget.result;

    final text = StringBuffer()
      ..writeln('SMARTBET AI — GIOCATA CONSIGLIATA')
      ..writeln()
      ..writeln(_matchLabel)
      ..writeln('Pronostico principale: ${result.prediction}')
      ..writeln(
        'Quota interessante: ${preview.outcome} '
        '@ ${preview.odd.toStringAsFixed(2)}',
      );

    if (preview.bookmaker.trim().isNotEmpty) {
      text.writeln('Bookmaker: ${preview.bookmaker}');
    }

    text
      ..writeln(
        'Stake consigliato: ${preview.stakePercent.toStringAsFixed(2)}%',
      )
      ..writeln(
        'Importo sul bankroll attuale: '
        '€${preview.stakeAmount.toStringAsFixed(2)}',
      )
      ..writeln('Smart Score: ${result.smartScore}')
      ..writeln('Rischio: ${result.risk}')
      ..writeln()
      ..writeln(
        'Analisi statistica a scopo informativo. '
        'Gioca responsabilmente.',
      );

    await SharePlus.instance.share(
      ShareParams(text: text.toString(), subject: 'SmartBet AI — $_matchLabel'),
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
                          'OVER / UNDER 1.5',
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
                            'OVER 1.5',
                            result.over15Probability,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _probabilityBox(
                            'UNDER 1.5',
                            result.under15Probability,
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
              // GIOCATA CONSIGLIATA / REGISTRAZIONE
              // =================================================
              _betExecutionCard(preview),

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
              // QUOTA INTERESSANTE
              // =================================================
              _sectionCard(
                title: 'QUOTA INTERESSANTE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
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
                    const SizedBox(height: 8),
                    Text(
                      result.shouldBet
                          ? 'La quota disponibile è interessante rispetto '
                                'alla probabilità stimata da SmartBet.'
                          : 'SmartBet non rileva al momento una quota '
                                'sufficientemente interessante da giocare.',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
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
        result[currentSection] = cleaned;
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
                'GIOCATA CONSIGLIATA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (!preview.canPlaceBet) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'SmartBet non rileva al momento una quota '
                'sufficientemente interessante da consigliare. '
                'Puoi comunque registrare manualmente la giocata '
                'che hai effettivamente effettuato.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),

            const SizedBox(height: 16),

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
                onPressed: _registering
                    ? null
                    : () => _openRegisterBetDialog(preview),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('REGISTRA GIOCATA MANUALMENTE'),
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
          ] else ...[
            _betRow('Esito', preview.outcome),

            _betRow('Quota', preview.odd.toStringAsFixed(2)),

            _betRow('Bookmaker', preview.bookmaker),

            const Divider(color: Colors.white12, height: 28),

            _betRow(
              'Percentuale consigliata',
              '${preview.stakePercent.toStringAsFixed(2)}%',
            ),

            _betRow(
              'Importo da registrare',
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
                onPressed: _registering
                    ? null
                    : () => _openRegisterBetDialog(preview),
                icon: _registering
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_note_outlined),
                label: Text(
                  _registering ? 'REGISTRAZIONE...' : 'REGISTRA GIOCATA',
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

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _shareBet(preview),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('CONDIVIDI GIOCATA'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
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
