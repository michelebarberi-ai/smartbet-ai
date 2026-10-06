import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'goalvdline_comparison_result_resolver.dart';

class GoalVdLineComparisonSyncService {
  final GoalVdLineComparisonResultResolver _resolver;

  final Duration cooldown;

  GoalVdLineComparisonSyncService({
    GoalVdLineComparisonResultResolver? resolver,
    this.cooldown = const Duration(hours: 1),
  }) : _resolver = resolver ?? GoalVdLineComparisonResultResolver();

  static final GoalVdLineComparisonSyncService instance =
      GoalVdLineComparisonSyncService();

  static const String _lastAttemptKey =
      'goalvdline_comparison_result_sync_last_attempt_v1';

  Future<GoalVdLineResultResolutionSummary?>? _inFlight;

  // ============================================================
  // SYNC CON COOLDOWN
  // ============================================================

  Future<GoalVdLineResultResolutionSummary?> resolveIfDue({
    bool force = false,
    DateTime? now,
  }) {
    final running = _inFlight;

    if (running != null) {
      return running;
    }

    final run = _resolveIfDue(force: force, now: now);

    _inFlight = run;

    return run.whenComplete(() {
      if (identical(_inFlight, run)) {
        _inFlight = null;
      }
    });
  }

  Future<GoalVdLineResultResolutionSummary?> _resolveIfDue({
    required bool force,
    required DateTime? now,
  }) async {
    try {
      final currentTime = (now ?? DateTime.now()).toLocal();

      final prefs = SharedPreferencesAsync();

      if (!force) {
        final raw = await prefs.getString(_lastAttemptKey);

        final parsed = DateTime.tryParse(raw ?? '');

        if (parsed != null) {
          final elapsed = currentTime.difference(parsed.toLocal());

          if (!elapsed.isNegative && elapsed < cooldown) {
            return null;
          }
        }
      }

      // Registriamo l'inizio del tentativo PRIMA delle API.
      // Evita chiamate ripetute anche in caso di problemi rete.
      await prefs.setString(_lastAttemptKey, currentTime.toIso8601String());

      final summary = await _resolver.resolvePending(now: currentTime);

      debugPrint(
        'GoalVdLine comparison sync: '
        'resolved=${summary.resolved}, '
        'pending=${summary.unresolvedAfter}, '
        'dates=${summary.datesQueried}, '
        'apiErrors=${summary.apiErrors}',
      );

      return summary;
    } catch (error, stackTrace) {
      // Questa funzione è diagnostica:
      // non deve mai compromettere l'app.
      debugPrint('GoalVdLine comparison sync error: $error');

      debugPrint(stackTrace.toString());

      return null;
    }
  }
}
