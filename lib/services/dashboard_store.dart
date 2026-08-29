import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_result.dart';
import '../repositories/match_repository.dart';
import 'live_match_service.dart';
import 'italy_schedule_filter.dart';
import 'smartbet_ai_service.dart';

class DashboardStore extends ChangeNotifier {
  DashboardStore._();

  static final DashboardStore instance = DashboardStore._();

  // ============================================================
  // CHIAVI PERSISTENZA
  // ============================================================

  static const String _keyAnalysesPerformed = 'dashboard_analyses_performed';

  static const String _keyValueBetsFound = 'dashboard_value_bets_found';

  static const String _keyPremiumBetsFound = 'dashboard_premium_bets_found';

  static const String _keyConfidenceTotal = 'dashboard_confidence_total';

  // ============================================================
  // STATO
  // ============================================================

  bool _initialized = false;
  bool _loading = false;

  bool _aiOnline = false;

  int? _todayMatches;
  int? _liveMatches;

  int _analysesPerformed = 0;
  int _valueBetsFound = 0;
  int _premiumBetsFound = 0;
  int _confidenceTotal = 0;

  DateTime? _lastUpdate;

  // ============================================================
  // GETTERS
  // ============================================================

  bool get initialized => _initialized;

  bool get loading => _loading;

  bool get aiOnline => _aiOnline;

  int? get todayMatches => _todayMatches;

  int? get liveMatches => _liveMatches;

  int get analysesPerformed => _analysesPerformed;

  int? get valueBets {
    if (_analysesPerformed == 0) {
      return null;
    }

    return _valueBetsFound;
  }

  int? get premiumBets {
    if (_analysesPerformed == 0) {
      return null;
    }

    return _premiumBetsFound;
  }

  double? get reliability {
    if (_analysesPerformed == 0) {
      return null;
    }

    return _confidenceTotal / _analysesPerformed;
  }

  DateTime? get lastUpdate => _lastUpdate;

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    await _loadSavedStatistics();

    await refresh();
  }

  // ============================================================
  // CARICA STATISTICHE SALVATE
  // ============================================================

  Future<void> _loadSavedStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _analysesPerformed = prefs.getInt(_keyAnalysesPerformed) ?? 0;

      _valueBetsFound = prefs.getInt(_keyValueBetsFound) ?? 0;

      _premiumBetsFound = prefs.getInt(_keyPremiumBetsFound) ?? 0;

      _confidenceTotal = prefs.getInt(_keyConfidenceTotal) ?? 0;
    } catch (e) {
      debugPrint('Dashboard persistence load error: $e');
    }
  }

  // ============================================================
  // SALVA STATISTICHE
  // ============================================================

  Future<void> _saveStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt(_keyAnalysesPerformed, _analysesPerformed);

      await prefs.setInt(_keyValueBetsFound, _valueBetsFound);

      await prefs.setInt(_keyPremiumBetsFound, _premiumBetsFound);

      await prefs.setInt(_keyConfidenceTotal, _confidenceTotal);
    } catch (e) {
      debugPrint('Dashboard persistence save error: $e');
    }
  }

  // ============================================================
  // REFRESH
  // ============================================================

  Future<void> refresh() async {
    if (_loading) {
      return;
    }

    _loading = true;

    notifyListeners();

    await Future.wait([
      _loadTodayMatches(),
      _loadLiveMatches(),
      _checkBackend(),
    ]);

    _lastUpdate = DateTime.now();

    _loading = false;

    notifyListeners();
  }

  Future<void> _loadLiveMatches() async {
    try {
      final matches = await LiveMatchService().getLiveMatches();
      _liveMatches = matches.length;
    } catch (e) {
      debugPrint('Dashboard live matches error: $e');
      _liveMatches = null;
    }
  }

  // ============================================================
  // PARTITE OGGI
  // ============================================================

  Future<void> _loadTodayMatches() async {
    try {
      final matches = await MatchRepository.getTodayMatches().timeout(
        const Duration(seconds: 8),
      );

      final now = DateTime.now();

      final analyzable = matches.where((match) {
        if (!match.hasTeamIds) {
          return false;
        }

        DateTime matchDate;

        try {
          matchDate = DateTime.parse(match.date).toLocal();
        } catch (_) {
          return false;
        }

        if (!matchDate.isAfter(now)) {
          return false;
        }

        if (!ItalyScheduleFilter.allows(match)) {
          return false;
        }

        return true;
      }).length;

      _todayMatches = analyzable;
      _aiOnline = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Dashboard matches error: $e');
      _todayMatches = null;
      notifyListeners();
    }
  }

  // ============================================================
  // BACKEND AI
  // ============================================================

  Future<void> _checkBackend() async {
    try {
      final uri = Uri.parse(SmartBetAiService.backendUrl);

      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      // Anche 404 significa che Express ha risposto
      // ed è quindi raggiungibile.
      _aiOnline = response.statusCode > 0;
    } catch (_) {
      _aiOnline = false;
    }
  }

  // ============================================================
  // REGISTRA ANALISI ESEGUITA
  // ============================================================

  Future<void> registerAnalysis(AnalysisResult result) async {
    // Non conteggiamo risultati di errore.
    if (result.smartScore <= 0) {
      return;
    }

    _analysesPerformed++;

    _confidenceTotal += result.smartScore;

    // ==========================================================
    // VALUE BET
    // ==========================================================

    if (result.shouldBet) {
      _valueBetsFound++;

      // ========================================================
      // PREMIUM
      // ========================================================
      //
      // Una Premium è una Value Bet con Smart Score >= 75.
      //
      // Quindi:
      // - deve essere realmente giocabile
      // - deve superare i criteri shouldBet
      // - deve avere qualità AI elevata
      //
      // Non è un numero inventato.
      // ========================================================

      if (result.smartScore >= 75) {
        _premiumBetsFound++;
      }
    }

    _lastUpdate = DateTime.now();

    await _saveStatistics();

    notifyListeners();
  }

  // ============================================================
  // RESET STATISTICHE DASHBOARD
  // ============================================================

  Future<void> resetStatistics() async {
    _analysesPerformed = 0;
    _valueBetsFound = 0;
    _premiumBetsFound = 0;
    _confidenceTotal = 0;

    _lastUpdate = DateTime.now();

    await _saveStatistics();

    notifyListeners();
  }
}
