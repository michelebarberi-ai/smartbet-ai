import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences only. Saving locally does NOT register an APNs device or
/// guarantee delivery until the dedicated server-side push flow is enabled.
@immutable
class GoalVdLinePalinsestoDigestPreferences {
  const GoalVdLinePalinsestoDigestPreferences({
    this.requested = false,
    this.hour = 8,
    this.minute = 0,
  });

  final bool requested;
  final int hour;
  final int minute;

  bool get isValid =>
      hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;

  String get formattedHour =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  GoalVdLinePalinsestoDigestPreferences copyWith({
    bool? requested,
    int? hour,
    int? minute,
  }) =>
      GoalVdLinePalinsestoDigestPreferences(
        requested: requested ?? this.requested,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  Map<String, Object> toJson() => {
        'requested': requested,
        'hour': hour,
        'minute': minute,
      };

  static GoalVdLinePalinsestoDigestPreferences? fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['requested'] is! bool ||
        json['hour'] is! int ||
        json['minute'] is! int) {
      return null;
    }
    final result = GoalVdLinePalinsestoDigestPreferences(
      requested: json['requested'] as bool,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
    );
    return result.isValid ? result : null;
  }
}

class GoalVdLinePalinsestoDigestPreferencesStore {
  const GoalVdLinePalinsestoDigestPreferencesStore({
    this.preferencesLoader,
  });

  static const storageKey = 'goalvdline_palinsesto_daily_digest_v1';
  final Future<SharedPreferences> Function()? preferencesLoader;

  Future<SharedPreferences> _prefs() =>
      (preferencesLoader ?? SharedPreferences.getInstance)();

  Future<GoalVdLinePalinsestoDigestPreferences> load() async {
    try {
      final raw = (await _prefs()).getString(storageKey);
      if (raw == null) return const GoalVdLinePalinsestoDigestPreferences();
      return GoalVdLinePalinsestoDigestPreferences.fromJson(
            jsonDecode(raw),
          ) ??
          const GoalVdLinePalinsestoDigestPreferences();
    } catch (_) {
      return const GoalVdLinePalinsestoDigestPreferences();
    }
  }

  Future<bool> save(GoalVdLinePalinsestoDigestPreferences value) async {
    if (!value.isValid) return false;
    try {
      return await (await _prefs()).setString(
        storageKey, jsonEncode(value.toJson()),
      );
    } catch (_) {
      return false;
    }
  }
}
