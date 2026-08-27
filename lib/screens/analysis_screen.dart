import '../services/smartbet_ai_service.dart';
import '../services/smartbet_coupon_service.dart';
import '../services/review_coupon_store.dart';
import 'coupon_screen.dart';
import 'package:flutter/material.dart';
import '../ai/smartcore.dart';
import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import 'analysis_detail_screen.dart';
import 'smart_score_filtered_screen.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late Future<List<MatchModel>> _matches;

  final Set<String> _expandedCountries = {};
  final Set<String> _expandedLeagues = {};
  final Set<String> _expandedCompetitionTypes = {};

  // ============================================================
  // SCHEDINA SMARTBET
  // ============================================================

  final Map<int, MatchModel> _selectedMatches = {};

  // Evita di rilanciare SmartCore ogni volta che la schermata
  // viene ridisegnata o si apre/chiude una sezione.
  final Map<int, Future<AnalysisResult>> _analysisFutures = {};

  static const int _maximumCouponMatches = 12;

  bool _creatingCoupon = false;

  String _searchText = "";

  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();

    _selectedDate = _dateOnly(DateTime.now());
    _matches = MatchRepository.getTodayMatches();
  }

  // ============================================================
  // ERRORI RETE / API
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

    if (raw.contains('401') ||
        raw.contains('403') ||
        raw.contains('unauthorized') ||
        raw.contains('forbidden')) {
      return 'Il servizio dati non è momentaneamente disponibile. '
          'Riprova più tardi.';
    }

    return 'Si è verificato un problema durante il recupero dei dati. '
        'Riprova tra poco.';
  }

  void _retryMatches() {
    setState(() {
      _analysisFutures.clear();

      if (_isTodaySelected) {
        _matches = MatchRepository.getTodayMatches();
      } else {
        _matches = MatchRepository.getMatchesByDate(_selectedDate);
      }
    });
  }

  void _retryPreAnalysis(MatchModel match) {
    setState(() {
      _analysisFutures.remove(match.fixtureId);
    });
  }

  // ============================================================
  // SELEZIONE DATA
  // ============================================================

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool get _isTodaySelected {
    return _isSameDate(_selectedDate, _dateOnly(DateTime.now()));
  }

  Future<void> _selectDate(DateTime date) async {
    final normalized = _dateOnly(date);

    if (_isSameDate(normalized, _selectedDate)) {
      return;
    }

    setState(() {
      _selectedDate = normalized;

      _selectedMatches.clear();
      _analysisFutures.clear();
      _expandedCountries.clear();
      _expandedLeagues.clear();

      if (_isSameDate(normalized, _dateOnly(DateTime.now()))) {
        _matches = MatchRepository.getTodayMatches();
      } else {
        _matches = MatchRepository.getMatchesByDate(normalized);
      }
    });
  }

  Future<void> _openDatePicker() async {
    final today = _dateOnly(DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Scegli la data delle partite',
      cancelText: 'ANNULLA',
      confirmText: 'SELEZIONA',
    );

    if (picked == null || !mounted) {
      return;
    }

    await _selectDate(picked);
  }

  String _weekdayLabel(DateTime date) {
    const labels = <String>['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

    return labels[date.weekday - 1];
  }

  String _shortDateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month';
  }

  Widget _dateChip(DateTime date) {
    final selected = _isSameDate(date, _selectedDate);
    final today = _isSameDate(date, _dateOnly(DateTime.now()));

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _selectDate(date);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00C853) : const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF00C853) : Colors.white12,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                today ? 'Oggi' : _weekdayLabel(date),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _shortDateLabel(date),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateSelector() {
    final today = _dateOnly(DateTime.now());
    final dates = List<DateTime>.generate(
      7,
      (index) => today.add(Duration(days: index)),
    );

    final selectedOutsideWeek = !dates.any(
      (date) => _isSameDate(date, _selectedDate),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              color: Color(0xFF00C853),
              size: 18,
            ),
            const SizedBox(width: 7),
            const Text(
              'Scegli il giorno',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (!_isTodaySelected)
              TextButton(
                onPressed: () {
                  _selectDate(today);
                },
                child: const Text('TORNA A OGGI'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 62,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...dates.map(_dateChip),
              if (selectedOutsideWeek) _dateChip(_selectedDate),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openDatePicker,
                  child: Container(
                    width: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(
                      Icons.date_range,
                      color: Color(0xFF00C853),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SELEZIONE SCHEDINA
  // ============================================================

  bool _isSelected(MatchModel match) {
    return _selectedMatches.containsKey(match.fixtureId);
  }

  void _toggleSelection(MatchModel match) {
    setState(() {
      if (_selectedMatches.containsKey(match.fixtureId)) {
        _selectedMatches.remove(match.fixtureId);
        return;
      }

      if (_selectedMatches.length >= _maximumCouponMatches) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Puoi selezionare al massimo 12 partite per la schedina AI.',
            ),
          ),
        );

        return;
      }

      _selectedMatches[match.fixtureId] = match;
    });
  }

  void _clearSelections() {
    setState(() {
      _selectedMatches.clear();
    });
  }

  Future<void> _createCoupon() async {
    if (_creatingCoupon) {
      return;
    }

    if (_selectedMatches.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona almeno 2 partite.')),
      );

      return;
    }

    setState(() {
      _creatingCoupon = true;
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),

              const SizedBox(height: 20),

              const Text(
                'CREAZIONE SCHEDINA AI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                'SmartBet sta analizzando '
                '${_selectedMatches.length} partite...',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),

              const SizedBox(height: 8),

              const Text(
                'Dossier • Quote • Value Bet • Rischio • Selezione finale',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),

              const SizedBox(height: 12),

              const Text(
                'L’analisi può richiedere alcuni minuti.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );

    try {
      final service = SmartBetCouponService();

      final coupons = await service.buildCouponSet(
        matches: _selectedMatches.values.toList(),
        // Nella selezione manuale è meglio mostrare anche una sola
        // giocata realmente validata, invece di restituire sempre
        // "nessun risultato" quando una sola supera i filtri.
        minimumRequired: 1,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      if (!mounted) {
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CouponScreen(coupons: coupons)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyErrorMessage(e)),
          action: SnackBarAction(label: 'RIPROVA', onPressed: _createCoupon),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingCoupon = false;
        });
      }
    }
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
  // TIPO COMPETIZIONE
  // ============================================================

  String _competitionType(MatchModel match) {
    final type = match.leagueType.toLowerCase().trim();
    final league = match.league.toLowerCase().trim();

    // ----------------------------------------------------------
    // FEMMINILI
    // ----------------------------------------------------------

    if (type.contains('women') ||
        type.contains('female') ||
        league.contains('women') ||
        league.contains('woman') ||
        league.contains('femminile') ||
        league.contains('ladies')) {
      return 'Femminili';
    }

    // ----------------------------------------------------------
    // GIOVANILI
    // ----------------------------------------------------------

    if (type.contains('youth') ||
        league.contains('u17') ||
        league.contains('u18') ||
        league.contains('u19') ||
        league.contains('u20') ||
        league.contains('u21') ||
        league.contains('u23') ||
        league.contains('primavera') ||
        league.contains('youth')) {
      return 'Giovanili';
    }

    // ----------------------------------------------------------
    // AMICHEVOLI
    // ----------------------------------------------------------

    if (type.contains('friendly') ||
        league.contains('friendly') ||
        league.contains('friendlies') ||
        league.contains('amical')) {
      return 'Amichevoli';
    }

    // ----------------------------------------------------------
    // NAZIONALI
    // ----------------------------------------------------------

    if (type.contains('national')) {
      return 'Nazionali';
    }

    // ----------------------------------------------------------
    // COPPE INTERNAZIONALI
    // ----------------------------------------------------------

    if (type.contains('european') ||
        league.contains('champions league') ||
        league.contains('europa league') ||
        league.contains('conference league') ||
        league.contains('libertadores') ||
        league.contains('sudamericana')) {
      return 'Internazionali';
    }

    // ----------------------------------------------------------
    // COPPE NAZIONALI
    // ----------------------------------------------------------

    if (type.contains('cup') ||
        league.contains('coppa') ||
        league.contains('cup') ||
        league.contains('copa') ||
        league.contains('coupe') ||
        league.contains('pokal') ||
        league.contains('supercoppa') ||
        league.contains('super cup')) {
      return 'Coppe';
    }

    // ----------------------------------------------------------
    // CAMPIONATI
    // ----------------------------------------------------------

    if (type.contains('domestic') || type.contains('league')) {
      return 'Campionati';
    }

    return 'Altre competizioni';
  }

  Map<String, List<MatchModel>> _groupByCompetitionType(
    List<MatchModel> matches,
  ) {
    final grouped = <String, List<MatchModel>>{};

    for (final match in matches) {
      final type = _competitionType(match);

      grouped.putIfAbsent(type, () => []);
      grouped[type]!.add(match);
    }

    const order = <String>[
      'Campionati',
      'Coppe',
      'Internazionali',
      'Nazionali',
      'Femminili',
      'Giovanili',
      'Amichevoli',
      'Altre competizioni',
    ];

    final result = <String, List<MatchModel>>{};

    for (final type in order) {
      final items = grouped[type];

      if (items != null && items.isNotEmpty) {
        result[type] = items;
      }
    }

    return result;
  }

  IconData _competitionTypeIcon(String type) {
    switch (type) {
      case 'Campionati':
        return Icons.sports_soccer;

      case 'Coppe':
        return Icons.emoji_events;

      case 'Internazionali':
        return Icons.public;

      case 'Nazionali':
        return Icons.flag;

      case 'Femminili':
        return Icons.female;

      case 'Giovanili':
        return Icons.groups;

      case 'Amichevoli':
        return Icons.handshake;

      default:
        return Icons.folder_outlined;
    }
  }

  // ============================================================
  // FILTRO SMART SCORE - APRE PAGINA DEDICATA
  // ============================================================

  Future<void> _openSmartScoreFilter(int minimum) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmartScoreFilteredScreen(
          selectedDate: _selectedDate,
          minimumSmartScore: minimum,
        ),
      ),
    );
  }

  Widget _smartScoreFilters() {
    Widget chip(String label, {required bool selected, VoidCallback? onTap}) {
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          onTap?.call();
        },
        selectedColor: const Color(0xFF00C853),
        backgroundColor: const Color(0xFF1F2937),
        side: BorderSide(
          color: selected ? const Color(0xFF00C853) : Colors.white12,
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        showCheckmark: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.filter_alt_outlined, color: Color(0xFF00C853), size: 18),
            SizedBox(width: 7),
            Text(
              'Affidabilità pre-analisi',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip('Tutte', selected: true),
              const SizedBox(width: 8),
              chip(
                '≥55',
                selected: false,
                onTap: () => _openSmartScoreFilter(55),
              ),
              const SizedBox(width: 8),
              chip(
                '≥60',
                selected: false,
                onTap: () => _openSmartScoreFilter(60),
              ),
              const SizedBox(width: 8),
              chip(
                '≥65',
                selected: false,
                onTap: () => _openSmartScoreFilter(65),
              ),
              const SizedBox(width: 8),
              chip(
                '≥75',
                selected: false,
                onTap: () => _openSmartScoreFilter(75),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Toccando un filtro si apre una pagina dedicata '
          'con le sole partite che raggiungono la soglia scelta.',
          style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.35),
        ),
      ],
    );
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
  // CACHE ANALISI PRELIMINARE
  // ============================================================

  Future<AnalysisResult> _analysisFutureFor(MatchModel match) {
    return _analysisFutures.putIfAbsent(
      match.fixtureId,
      () => SmartCore.analyze(match),
    );
  }

  // ============================================================
  // CARD PARTITA
  // ============================================================

  Widget _matchCard(BuildContext context, MatchModel match) {
    return FutureBuilder<AnalysisResult>(
      future: _analysisFutureFor(match),
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
                    '${match.homeTeam} - ${match.awayTeam}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.orangeAccent,
                        size: 19,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Analisi non disponibile',
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _friendlyErrorMessage(snapshot.error),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _retryPreAnalysis(match),
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('RIPROVA'),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'PRE-ANALISI',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          result.prediction,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
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
                        "Convenienza quota: ${result.valueBet}",
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

                // =================================================
                // SELEZIONE SCHEDINA
                // =================================================
                InkWell(
                  onTap: () {
                    _toggleSelection(match);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: _isSelected(match)
                          ? const Color(0xFF00C853).withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isSelected(match)
                            ? const Color(0xFF00C853)
                            : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isSelected(match)
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          color: _isSelected(match)
                              ? const Color(0xFF00C853)
                              : Colors.white54,
                          size: 21,
                        ),

                        const SizedBox(width: 9),

                        Expanded(
                          child: Text(
                            _isSelected(match)
                                ? 'SELEZIONATA PER SCHEDINA AI'
                                : 'AGGIUNGI ALLA SCHEDINA AI',
                            style: TextStyle(
                              color: _isSelected(match)
                                  ? const Color(0xFF00C853)
                                  : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final result = await ReviewCouponStore.addMatch(match);

                    if (!context.mounted) {
                      return;
                    }

                    switch (result) {
                      case 'added':
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Partita aggiunta alla Revisione Schedina AI.',
                            ),
                          ),
                        );
                        break;

                      case 'duplicate':
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Questa partita è già presente nella Revisione Schedina AI.',
                            ),
                          ),
                        );
                        break;

                      case 'full':
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Hai già raggiunto il limite di 12 partite nella Revisione Schedina AI.',
                            ),
                          ),
                        );
                        break;
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.55),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          color: Colors.orangeAccent,
                          size: 21,
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'AGGIUNGI A REVISIONE SCHEDINA',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                const SizedBox(height: 10),

                // ANALIZZA
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      // ========================================================
                      // LOADING
                      // ========================================================

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

                                SizedBox(height: 6),

                                Text(
                                  'Dossier • Quote • AI • Value Bet • Stake',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );

                      // ========================================================
                      // SMARTBET AI AVANZATA
                      // ========================================================

                      try {
                        final advancedResult = await SmartBetAiService()
                            .analyzeMatch(match);

                        if (!context.mounted) {
                          return;
                        }

                        Navigator.of(context, rootNavigator: true).pop();

                        if (!context.mounted) {
                          return;
                        }

                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AnalysisDetailScreen(
                              match: match,
                              result: advancedResult,
                            ),
                          ),
                        );
                      } catch (e) {
                        if (!context.mounted) {
                          return;
                        }

                        Navigator.of(context, rootNavigator: true).pop();

                        if (!context.mounted) {
                          return;
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_friendlyErrorMessage(e))),
                        );
                      }
                    },
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
  // SEZIONE TIPO COMPETIZIONE
  // ============================================================

  Widget _competitionTypeSection(
    BuildContext context,
    String country,
    String type,
    List<MatchModel> matches,
  ) {
    final key = '$country::$type';

    final expanded = _expandedCompetitionTypes.contains(key);

    final leagues = _groupByLeague(matches);

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedCompetitionTypes.remove(key);
              } else {
                _expandedCompetitionTypes.add(key);
              }
            });
          },
          borderRadius: BorderRadius.circular(13),
          child: Container(
            margin: const EdgeInsets.fromLTRB(18, 4, 12, 7),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF172033),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: expanded
                    ? const Color(0xFF00C853).withValues(alpha: 0.35)
                    : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _competitionTypeIcon(type),
                  color: expanded ? const Color(0xFF00C853) : Colors.white54,
                  size: 21,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    type,
                    style: TextStyle(
                      color: expanded ? Colors.white : Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${matches.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(width: 7),

                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: expanded ? const Color(0xFF00C853) : Colors.white38,
                ),
              ],
            ),
          ),
        ),

        if (expanded)
          ...leagues.entries.map(
            (entry) => _leagueSection(context, country, entry.key, entry.value),
          ),
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
    final competitionTypes = _groupByCompetitionType(matches);

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
          ...competitionTypes.entries.map(
            (entry) => _competitionTypeSection(
              context,
              country,
              entry.key,
              entry.value,
            ),
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

          _dateSelector(),

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

          const SizedBox(height: 14),

          _smartScoreFilters(),
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

      bottomNavigationBar: _selectedMatches.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF172033),
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Svuota selezione',
                      onPressed: _creatingCoupon ? null : _clearSelections,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white54,
                      ),
                    ),

                    const SizedBox(width: 6),

                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _creatingCoupon ? null : _createCoupon,
                        icon: _creatingCoupon
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(
                          _creatingCoupon
                              ? 'CREAZIONE...'
                              : 'CREA SCHEDINA AI (${_selectedMatches.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

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
            return Column(
              children: [
                _header(),
                Expanded(
                  child: Center(
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
                          const SizedBox(height: 16),
                          const Text(
                            'Servizio dati non raggiungibile',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _friendlyErrorMessage(snapshot.error),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _retryMatches,
                            icon: const Icon(Icons.refresh),
                            label: const Text('RIPROVA'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF00C853),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 13,
                              ),
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
