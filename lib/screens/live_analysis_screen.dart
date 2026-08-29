import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/live_analysis_engine.dart';
import '../services/live_match_service.dart';

class LiveAnalysisScreen extends StatefulWidget {
  const LiveAnalysisScreen({super.key});

  @override
  State<LiveAnalysisScreen> createState() => _LiveAnalysisScreenState();
}

class _LiveAnalysisScreenState extends State<LiveAnalysisScreen> {
  final LiveMatchService _service = LiveMatchService();
  final TextEditingController _searchController = TextEditingController();

  Future<List<LiveMatchSummary>>? _future;
  Timer? _timer;

  bool _mainCompetitionsOnly = false;

  @override
  void initState() {
    super.initState();

    _future = _service.getLiveMatches();

    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;

    setState(() {
      _future = _service.getLiveMatches();
    });
  }

  Future<void> _manualRefresh() async {
    final future = _service.getLiveMatches();

    setState(() {
      _future = future;
    });

    await future;
  }

  bool _isMainCompetition(LiveMatchSummary match) {
    final league = match.leagueName.toLowerCase().trim();
    final country = match.country.toLowerCase().trim();

    const internationalPatterns = [
      'champions league',
      'europa league',
      'conference league',
      'super cup',
      'world cup',
      'club world cup',
      'euro championship',
      'nations league',
      'copa america',
      'libertadores',
      'sudamericana',
    ];

    if (internationalPatterns.any(league.contains)) {
      return true;
    }

    bool containsAny(List<String> patterns) {
      return patterns.any(league.contains);
    }

    switch (country) {
      case 'italy':
        return containsAny(['serie a', 'serie b', 'coppa italia']);

      case 'england':
        return containsAny([
          'premier league',
          'championship',
          'fa cup',
          'league cup',
          'efl cup',
        ]);

      case 'spain':
        return containsAny(['la liga', 'laliga', 'segunda', 'copa del rey']);

      case 'germany':
        return containsAny(['bundesliga', 'dfb pokal']);

      case 'france':
        return containsAny(['ligue 1', 'ligue 2', 'coupe de france']);

      case 'netherlands':
        return containsAny(['eredivisie']);

      case 'portugal':
        return containsAny(['primeira liga', 'liga portugal']);

      case 'belgium':
        return containsAny(['jupiler', 'pro league']);

      case 'turkey':
      case 'türkiye':
        return containsAny(['süper lig', 'super lig']);

      case 'poland':
        return containsAny(['ekstraklasa', 'i liga']);

      case 'scotland':
        return containsAny(['premiership', 'championship']);

      case 'austria':
        return containsAny(['bundesliga', '2. liga']);

      case 'switzerland':
        return containsAny(['super league', 'challenge league']);

      case 'greece':
        return containsAny(['super league']);

      case 'denmark':
        return containsAny(['superliga']);

      case 'norway':
        return containsAny(['eliteserien']);

      case 'sweden':
        return containsAny(['allsvenskan']);

      case 'croatia':
        return containsAny(['hnl']);

      case 'serbia':
        return containsAny(['super liga']);

      case 'ukraine':
        return containsAny(['premier league']);

      case 'czech-republic':
      case 'czech republic':
        return containsAny(['czech liga', 'first league', 'chance liga']);

      case 'brazil':
        return containsAny(['serie a', 'copa do brasil']);

      case 'argentina':
        return containsAny([
          'liga profesional',
          'primera división',
          'primera division',
        ]);

      case 'usa':
      case 'united states':
        return containsAny(['major league soccer', 'mls']);

      default:
        return false;
    }
  }

  List<LiveMatchSummary> _filteredMatches(List<LiveMatchSummary> matches) {
    final query = _searchController.text.trim().toLowerCase();

    return matches.where((match) {
      if (_mainCompetitionsOnly && !_isMainCompetition(match)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return match.homeTeam.toLowerCase().contains(query) ||
          match.awayTeam.toLowerCase().contains(query) ||
          match.leagueName.toLowerCase().contains(query) ||
          match.country.toLowerCase().contains(query);
    }).toList();
  }

  Widget _filters(int totalMatches, int visibleMatches) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Cerca squadra o campionato',
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
            filled: true,
            fillColor: const Color(0xFF1F2937),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const SizedBox(
                  width: double.infinity,
                  child: Text('TUTTE', textAlign: TextAlign.center),
                ),
                selected: !_mainCompetitionsOnly,
                showCheckmark: false,
                selectedColor: const Color(0xFF00C853),
                backgroundColor: const Color(0xFF1F2937),
                labelStyle: TextStyle(
                  color: !_mainCompetitionsOnly ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) {
                  setState(() {
                    _mainCompetitionsOnly = false;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const SizedBox(
                  width: double.infinity,
                  child: Text('PRINCIPALI', textAlign: TextAlign.center),
                ),
                selected: _mainCompetitionsOnly,
                showCheckmark: false,
                selectedColor: const Color(0xFF00C853),
                backgroundColor: const Color(0xFF1F2937),
                labelStyle: TextStyle(
                  color: _mainCompetitionsOnly ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) {
                  setState(() {
                    _mainCompetitionsOnly = true;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$visibleMatches di $totalMatches partite Live',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      ],
    );
  }

  String _minuteLabel(LiveMatchSummary match) {
    final status = match.statusShort.toUpperCase();

    if (status == 'HT') {
      return 'Intervallo';
    }

    if (status == 'BT') {
      return 'Pausa';
    }

    if (match.elapsed <= 0) {
      return match.statusLong;
    }

    return "${match.elapsed}'";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Analisi Live AI'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna',
          ),
        ],
      ),
      body: FutureBuilder<List<LiveMatchSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final matches = snapshot.data ?? const <LiveMatchSummary>[];
          final visibleMatches = _filteredMatches(matches);

          if (matches.isEmpty) {
            return RefreshIndicator(
              onRefresh: _manualRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.sports_soccer, size: 58, color: Colors.white24),
                  SizedBox(height: 18),
                  Text(
                    'Nessuna partita in diretta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Quando saranno disponibili partite live compariranno qui automaticamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, height: 1.4),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _manualRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.redAccent, size: 14),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'LIVE • aggiornamento automatico ogni 30 secondi',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _filters(matches.length, visibleMatches.length),
                const SizedBox(height: 16),
                if (visibleMatches.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.search_off, color: Colors.white30, size: 36),
                        SizedBox(height: 10),
                        Text(
                          'Nessuna partita corrisponde ai filtri',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ...visibleMatches.map(
                  (match) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                _LiveMatchDetailScreen(match: match),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  _minuteLabel(match),
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Flexible(
                                  child: Text(
                                    match.leagueName,
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    match.homeTeam,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${match.homeGoals} - ${match.awayGoals}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    match.awayTeam,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'ANALIZZA LIVE',
                                  style: TextStyle(
                                    color: Color(0xFF00C853),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFF00C853),
                                  size: 18,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LiveMatchDetailScreen extends StatefulWidget {
  final LiveMatchSummary match;

  const _LiveMatchDetailScreen({required this.match});

  @override
  State<_LiveMatchDetailScreen> createState() => _LiveMatchDetailScreenState();
}

class _LiveMatchDetailScreenState extends State<_LiveMatchDetailScreen> {
  final LiveMatchService _service = LiveMatchService();

  Future<_LiveDetailData>? _future;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _future = _load();

    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<_LiveDetailData> _load() async {
    var currentMatch = widget.match;

    try {
      final liveMatches = await _service.getLiveMatches();

      for (final item in liveMatches) {
        if (item.fixtureId == widget.match.fixtureId) {
          currentMatch = item;
          break;
        }
      }
    } catch (_) {}

    final snapshot = await _service.getSnapshot(currentMatch);
    final analysis = LiveAnalysisEngine.analyze(snapshot);

    return _LiveDetailData(snapshot: snapshot, analysis: analysis);
  }

  void _reload() {
    if (!mounted) return;

    setState(() {
      _future = _load();
    });
  }

  Future<void> _manualRefresh() async {
    final future = _load();

    setState(() {
      _future = future;
    });

    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Analisi Live AI'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<_LiveDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorView(
              message:
                  snapshot.error?.toString() ?? 'Dati Live non disponibili.',
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;
          final match = data.snapshot.match;
          final analysis = data.analysis;

          return RefreshIndicator(
            onRefresh: _manualRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _scoreHeader(match),
                const SizedBox(height: 16),
                _analysisSummary(analysis),
                const SizedBox(height: 16),
                const Text(
                  'Probabilità Live',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _probabilityCard(
                  title: 'Almeno 1 altro gol',
                  value: analysis.atLeastOneMoreGoalProbability,
                  icon: Icons.add_circle_outline,
                ),
                _probabilityCard(
                  title: 'Almeno 2 altri gol',
                  value: analysis.atLeastTwoMoreGoalsProbability,
                  icon: Icons.exposure_plus_2,
                ),
                _probabilityCard(
                  title: '${match.homeTeam} segna ancora',
                  value: analysis.homeScoresProbability,
                  icon: Icons.home,
                ),
                _probabilityCard(
                  title: '${match.awayTeam} segna ancora',
                  value: analysis.awayScoresProbability,
                  icon: Icons.flight_takeoff,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Prossimo gol',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _probabilityCard(
                  title: match.homeTeam,
                  value: analysis.nextGoalHomeProbability,
                  icon: Icons.sports_soccer,
                ),
                _probabilityCard(
                  title: match.awayTeam,
                  value: analysis.nextGoalAwayProbability,
                  icon: Icons.sports_soccer,
                ),
                _probabilityCard(
                  title: 'Nessun altro gol',
                  value: analysis.noMoreGoalProbability,
                  icon: Icons.block,
                ),
                const SizedBox(height: 16),
                _liveStats(data.snapshot),
                if (data.snapshot.events.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _events(data.snapshot.events),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Analisi statistica Live a scopo informativo. '
                  'Le probabilità cambiano con l’andamento della partita.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _scoreHeader(LiveMatchSummary match) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB91C1C), Color(0xFF7F1D1D)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.circle, size: 10, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                "LIVE • ${match.elapsed}'",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${match.homeTeam}  ${match.homeGoals} - ${match.awayGoals}  ${match.awayTeam}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            match.leagueName,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _analysisSummary(LiveAnalysisResult analysis) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            analysis.dataQuality == 'Limitati' || analysis.confidence < 55
                ? 'STIMA PRELIMINARE LIVE'
                : 'SMARTBET LIVE',
            style: const TextStyle(
              color: Color(0xFF00C853),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            analysis.summary,
            style: const TextStyle(color: Colors.white, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip('Pressione: ${analysis.pressureTeam}'),
              _infoChip('Affidabilità ${analysis.confidence}%'),
              _infoChip('Dati ${analysis.dataQuality}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _probabilityCard({
    required String title,
    required int value,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00C853), size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: value / 100,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(20),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$value%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveStats(LiveMatchSnapshot snapshot) {
    final home = snapshot.homeStats;
    final away = snapshot.awayStats;

    if (!snapshot.statisticsAvailable) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Column(
          children: [
            Icon(Icons.query_stats, color: Colors.white30, size: 34),
            SizedBox(height: 10),
            Text(
              'Statistiche Live non disponibili',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Per questa partita il provider fornisce risultato ed eventi, '
              'ma non tiri, possesso, corner e altre statistiche Live.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Text(
            'Statistiche Live',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          _statRow('Tiri in porta', home.shotsOnGoal, away.shotsOnGoal),
          _statRow('Tiri totali', home.totalShots, away.totalShots),
          _statRow('Tiri in area', home.shotsInsideBox, away.shotsInsideBox),
          _statRow('Possesso', home.possession, away.possession, suffix: '%'),
          _statRow('Corner', home.corners, away.corners),
          _statRow('Cartellini rossi', home.redCards, away.redCards),
          if (home.expectedGoals != null || away.expectedGoals != null)
            _statRow(
              'xG',
              home.expectedGoals ?? 0,
              away.expectedGoals ?? 0,
              decimals: 2,
            ),
        ],
      ),
    );
  }

  Widget _statRow(
    String label,
    double home,
    double away, {
    String suffix = '',
    int decimals = 0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              '${home.toStringAsFixed(decimals)}$suffix',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              '${away.toStringAsFixed(decimals)}$suffix',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _events(List<LiveMatchEvent> events) {
    final recent = events.reversed.take(8).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Eventi recenti',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...recent.map((event) {
            final minute = event.extra > 0
                ? "${event.elapsed}+${event.extra}'"
                : "${event.elapsed}'";

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      minute,
                      style: const TextStyle(
                        color: Color(0xFF00C853),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${event.teamName} • ${event.type} • ${event.detail}'
                      '${event.playerName.isEmpty ? '' : ' • ${event.playerName}'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _LiveDetailData {
  final LiveMatchSnapshot snapshot;
  final LiveAnalysisResult analysis;

  const _LiveDetailData({required this.snapshot, required this.analysis});
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off, size: 54, color: Colors.white30),
            const SizedBox(height: 16),
            const Text(
              'Dati Live non disponibili',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('RIPROVA'),
            ),
          ],
        ),
      ),
    );
  }
}
