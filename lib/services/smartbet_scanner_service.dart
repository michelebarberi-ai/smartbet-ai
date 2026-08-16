import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import '../repositories/match_repository.dart';
import 'dashboard_store.dart';
import 'smartbet_ai_service.dart';

class SmartBetScannerService extends ChangeNotifier {
  SmartBetScannerService._();

  static final SmartBetScannerService instance = SmartBetScannerService._();

  // ============================================================
  // STATO
  // ============================================================

  bool _scanning = false;
  bool _cancelRequested = false;

  int _totalMatches = 0;
  int _processedMatches = 0;
  int _successfulAnalyses = 0;
  int _failedAnalyses = 0;

  MatchModel? _currentMatch;

  final List<SmartBetScanResult> _results = [];

  // ============================================================
  // GETTERS
  // ============================================================

  bool get scanning => _scanning;

  int get totalMatches => _totalMatches;

  int get processedMatches => _processedMatches;

  int get successfulAnalyses => _successfulAnalyses;

  int get failedAnalyses => _failedAnalyses;

  MatchModel? get currentMatch => _currentMatch;

  List<SmartBetScanResult> get results => List.unmodifiable(_results);

  int get remainingMatches {
    final remaining = _totalMatches - _processedMatches;

    return remaining < 0 ? 0 : remaining;
  }

  double get progress {
    if (_totalMatches <= 0) {
      return 0.0;
    }

    return (_processedMatches / _totalMatches).clamp(0.0, 1.0);
  }

  // ============================================================
  // START SCAN
  // ============================================================

  Future<void> startScan() async {
    if (_scanning) {
      return;
    }

    _scanning = true;
    _cancelRequested = false;

    _totalMatches = 0;
    _processedMatches = 0;
    _successfulAnalyses = 0;
    _failedAnalyses = 0;

    _currentMatch = null;

    _results.clear();

    notifyListeners();

    try {
      // ========================================================
      // CARICA PARTITE SUPPORTATE SMARTBET
      // ========================================================

      final matches = await MatchRepository.getTodayMatches();

      _totalMatches = matches.length;

      notifyListeners();

      if (matches.isEmpty) {
        return;
      }

      final aiService = SmartBetAiService();

      try {
        // ======================================================
        // ANALISI SEQUENZIALE
        // ======================================================

        for (final match in matches) {
          if (_cancelRequested) {
            break;
          }

          _currentMatch = match;

          notifyListeners();

          try {
            final analysis = await aiService.analyzeMatch(match);

            // Risultato valido.
            if (analysis.smartScore > 0) {
              _successfulAnalyses++;

              _results.add(
                SmartBetScanResult(match: match, analysis: analysis),
              );

              // Aggiorna dashboard.
              await DashboardStore.instance.registerAnalysis(analysis);
            } else {
              _failedAnalyses++;
            }
          } catch (e) {
            _failedAnalyses++;

            debugPrint(
              'SmartBet Scanner error '
              '${match.homeTeam} - '
              '${match.awayTeam}: $e',
            );
          }

          _processedMatches++;

          notifyListeners();

          // Piccola pausa tra una partita e la successiva.
          //
          // Le singole API usano già ApiRateLimiter,
          // quindi questa pausa serve soltanto a non
          // martellare continuamente il backend AI.
          await Future.delayed(const Duration(milliseconds: 600));
        }
      } finally {
        aiService.dispose();
      }
    } catch (e) {
      debugPrint('SmartBet Scanner fatal error: $e');
    } finally {
      _scanning = false;
      _currentMatch = null;

      notifyListeners();
    }
  }

  // ============================================================
  // CANCEL
  // ============================================================

  void cancelScan() {
    if (!_scanning) {
      return;
    }

    _cancelRequested = true;

    notifyListeners();
  }

  // ============================================================
  // RESET RISULTATI
  // ============================================================

  void clearResults() {
    if (_scanning) {
      return;
    }

    _results.clear();

    _totalMatches = 0;
    _processedMatches = 0;
    _successfulAnalyses = 0;
    _failedAnalyses = 0;

    _currentMatch = null;

    notifyListeners();
  }
}

// ============================================================
// RISULTATO SCANSIONE
// ============================================================

class SmartBetScanResult {
  final MatchModel match;

  final AnalysisResult analysis;

  const SmartBetScanResult({required this.match, required this.analysis});

  bool get isValueBet => analysis.shouldBet;

  bool get isPremium {
    return analysis.shouldBet && analysis.smartScore >= 75;
  }
}
