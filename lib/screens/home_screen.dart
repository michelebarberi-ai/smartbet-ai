import 'package:flutter/material.dart';

import '../services/user_profile_store.dart';
import '../services/dashboard_store.dart';
import '../services/smartbet_analysis_comparison_store.dart';
import '../services/smartbet_analysis_history_store.dart';
import '../services/smartbet_analysis_result_resolver.dart';
import '../services/smartbet_learning_coordinator.dart';
import '../widgets/ai_card.dart';
import '../widgets/header.dart';
import '../widgets/menu_grid.dart';
import 'settings_screen.dart';

String _smartBetGreeting() {
  final hour = DateTime.now().hour;

  if (hour < 12) return 'Buongiorno';
  if (hour < 18) return 'Buon pomeriggio';
  return 'Buonasera';
}

Widget _smartBetHomeTopBar(BuildContext context) {
  final profile = UserProfileStore.instance;
  profile.initialize();

  return AnimatedBuilder(
    animation: profile,
    builder: (context, child) {
      final name = profile.name;
      final greeting = name.isEmpty
          ? _smartBetGreeting()
          : '${_smartBetGreeting()}, $name';

      return Row(
        children: [
          Expanded(
            child: Text(
              greeting,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
          ),
        ],
      );
    },
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DashboardStore _dashboard = DashboardStore.instance;

  final SmartBetAnalysisHistoryStore _analysisHistory =
      SmartBetAnalysisHistoryStore.instance;

  final SmartBetAnalysisComparisonStore _comparisonStore =
      SmartBetAnalysisComparisonStore.instance;

  late final SmartBetAnalysisResultResolver _analysisResolver;

  late final SmartBetLearningCoordinator _learningCoordinator;

  @override
  void initState() {
    super.initState();

    _analysisResolver = SmartBetAnalysisResultResolver(store: _analysisHistory);

    _learningCoordinator = SmartBetLearningCoordinator(
      historyStore: _analysisHistory,
      comparisonStore: _comparisonStore,
    );

    _dashboard.initialize();
    _refreshAnalysisHistory();
  }

  Future<void> _refreshAnalysisHistory() async {
    try {
      await Future.wait([
        _analysisHistory.initialize(),
        _comparisonStore.initialize(),
      ]);

      await _analysisResolver.resolvePending();

      await _learningCoordinator.refresh();
    } catch (e) {
      debugPrint('ANALYSIS HISTORY REFRESH ERROR: $e');
    }
  }

  Future<void> _refreshHome() async {
    await Future.wait([_dashboard.refresh(), _refreshAnalysisHistory()]);
  }

  // ============================================================
  // STAT CARD
  // ============================================================

  Widget _analysisMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _enginePerformanceCard({
    required String title,
    required SmartBetAnalysisEngineStats stats,
    required Color accent,
  }) {
    final accuracyColor = stats.settled > 0
        ? Colors.greenAccent
        : Colors.white54;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${stats.accuracy.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: accuracyColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Precisione sulle analisi concluse',
            style: TextStyle(color: Colors.white38, fontSize: 10.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _analysisMetric(
                label: 'Analizzate',
                value: '${stats.analyzed}',
                color: Colors.white,
              ),
              _analysisMetric(
                label: 'Concluse',
                value: '${stats.settled}',
                color: Colors.white70,
              ),
              _analysisMetric(
                label: 'In attesa',
                value: '${stats.pending}',
                color: stats.pending > 0 ? Colors.orangeAccent : Colors.white54,
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              _analysisMetric(
                label: 'Corrette',
                value: '${stats.correct}',
                color: Colors.greenAccent,
              ),
              _analysisMetric(
                label: 'Errate',
                value: '${stats.wrong}',
                color: Colors.redAccent,
              ),
              _analysisMetric(
                label: 'Precisione',
                value: '${stats.accuracy.toStringAsFixed(1)}%',
                color: accuracyColor,
              ),
            ],
          ),
          if (stats.unsupported > 0) ...[
            const SizedBox(height: 13),
            Text(
              '${stats.unsupported} analisi non verificabili automaticamente '
              'sono escluse dal calcolo della precisione.',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _comparisonOutcome({
    required String label,
    required int value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _directComparisonCard(SmartBetAnalysisComparisonStats stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.compare_arrows, color: Colors.purpleAccent, size: 22),
              SizedBox(width: 8),
              Text(
                'CONFRONTO DIRETTO',
                style: TextStyle(
                  color: Colors.purpleAccent,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'SmartBet e Diego vengono confrontati solo quando '
            'le due previsioni appartengono alla stessa analisi '
            'e sono entrambe verificabili.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 17),

          if (stats.linkedPairs == 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Text(
                'Il confronto inizierà con le prossime analisi '
                'SmartBet + Diego registrate insieme.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                _analysisMetric(
                  label: 'Coppie',
                  value: '${stats.linkedPairs}',
                  color: Colors.white,
                ),
                _analysisMetric(
                  label: 'Confrontabili',
                  value: '${stats.comparablePairs}',
                  color: Colors.white70,
                ),
                _analysisMetric(
                  label: 'In attesa',
                  value: '${stats.pendingPairs}',
                  color: stats.pendingPairs > 0
                      ? Colors.orangeAccent
                      : Colors.white54,
                ),
              ],
            ),

            const SizedBox(height: 17),

            Row(
              children: [
                _comparisonOutcome(
                  label: 'Entrambi\ncorretti',
                  value: stats.bothCorrect,
                  color: Colors.greenAccent,
                ),
                const SizedBox(width: 9),
                _comparisonOutcome(
                  label: 'Solo\nSmartBet',
                  value: stats.smartBetOnlyCorrect,
                  color: const Color(0xFF00C853),
                ),
              ],
            ),

            const SizedBox(height: 9),

            Row(
              children: [
                _comparisonOutcome(
                  label: 'Solo\nDiego',
                  value: stats.diegoOnlyCorrect,
                  color: Colors.lightBlueAccent,
                ),
                const SizedBox(width: 9),
                _comparisonOutcome(
                  label: 'Entrambi\nerrati',
                  value: stats.bothWrong,
                  color: Colors.redAccent,
                ),
              ],
            ),

            const SizedBox(height: 17),

            Row(
              children: [
                _analysisMetric(
                  label: 'Precisione SmartBet',
                  value: '${stats.smartBetAccuracy.toStringAsFixed(1)}%',
                  color: const Color(0xFF00C853),
                ),
                _analysisMetric(
                  label: 'Precisione Diego',
                  value: '${stats.diegoAccuracy.toStringAsFixed(1)}%',
                  color: Colors.lightBlueAccent,
                ),
              ],
            ),

            if (stats.unsupportedPairs > 0) ...[
              const SizedBox(height: 13),
              Text(
                '${stats.unsupportedPairs} coppie non verificabili '
                'automaticamente sono escluse dalle percentuali.',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final analysisHistory = _analysisHistory;
    final comparisonStore = _comparisonStore;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            dashboard,
            analysisHistory,
            comparisonStore,
          ]),
          builder: (context, child) {
            final smartBetStats = analysisHistory.statsFor(
              SmartBetAnalysisEngine.smartBet,
            );

            final diegoStats = analysisHistory.statsFor(
              SmartBetAnalysisEngine.diego,
            );

            final comparisonStats = comparisonStore.calculateStats(
              analysisRecords: analysisHistory.records,
            );

            return RefreshIndicator(
              onRefresh: _refreshHome,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                children: [
                  _smartBetHomeTopBar(context),
                  const SizedBox(height: 4),
                  const HomeHeader(),
                  AiCard(
                    online: dashboard.aiOnline,
                    loading: dashboard.loading,
                    liveMatches: dashboard.liveMatches,
                    todayMatches: dashboard.todayMatches,
                    analysesPerformed: dashboard.analysesPerformed,
                    lastUpdate: dashboard.lastUpdate,
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'Prestazioni analisi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Misura nel tempo la precisione delle previsioni '
                    'prodotte da SmartBet e Diego. Ogni selezione unica '
                    'viene conteggiata una sola volta, indipendentemente '
                    'da quante schermate la utilizzano.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 18),

                  _enginePerformanceCard(
                    title: 'SMARTBET',
                    stats: smartBetStats,
                    accent: const Color(0xFF00C853),
                  ),

                  const SizedBox(height: 14),

                  _enginePerformanceCard(
                    title: 'DIEGO',
                    stats: diegoStats,
                    accent: Colors.lightBlueAccent,
                  ),

                  const SizedBox(height: 14),

                  _directComparisonCard(comparisonStats),

                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.autorenew,
                          color: Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            smartBetStats.analyzed == 0 &&
                                    diegoStats.analyzed == 0
                                ? 'Le statistiche inizieranno a popolarsi '
                                      'con le prossime analisi effettuate '
                                      'nell’app.'
                                : 'Gli esiti delle partite concluse vengono '
                                      'controllati automaticamente. Le analisi '
                                      'non ancora concluse restano in attesa.',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 35),

                  const Text(
                    'I tuoi strumenti',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 18),
                  const MenuGrid(),
                  const SizedBox(height: 25),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
