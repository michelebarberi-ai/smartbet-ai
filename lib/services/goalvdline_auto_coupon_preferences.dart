import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Preferenze per la futura generazione programmata di AutoSchedina.
///
/// Salvare queste impostazioni NON crea un job sul server e NON abilita
/// notifiche push: il provisioning remoto sarà un passaggio separato.
class GoalVdLineAutoCouponPreferences {
  static const String multiMarket = 'MULTI';
  static const String overUnder = 'OVER_UNDER';
  static const String goalNoGoal = 'GOAL_NOGOAL';
  static const String oneXTwo = '1X2';
  static const String single = 'SINGLE';
  static const String threeSameFixtures = 'THREE_SAME_FIXTURES';
  static const List<String> allowedMarkets = [
    multiMarket,
    overUnder,
    goalNoGoal,
    oneXTwo,
  ];

  final bool requested;
  final int hour;
  final int minute;
  final int events;
  final int minimumMarketProbability;
  final String market;
  final bool notifyChanges;
  final String systemMode;

  const GoalVdLineAutoCouponPreferences({
    this.requested = false,
    this.hour = 8,
    this.minute = 0,
    this.events = 6,
    this.minimumMarketProbability = 65,
    this.market = multiMarket,
    this.notifyChanges = true,
    this.systemMode = threeSameFixtures,
  });

  bool get isValid =>
      hour >= 0 &&
      hour <= 23 &&
      minute >= 0 &&
      minute <= 59 &&
      events >= 3 &&
      events <= 15 &&
      minimumMarketProbability >= 50 &&
      minimumMarketProbability <= 90 &&
      minimumMarketProbability % 5 == 0 &&
      allowedMarkets.contains(market) &&
      (systemMode == single || systemMode == threeSameFixtures);

  String get formattedTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  GoalVdLineAutoCouponPreferences copyWith({
    bool? requested,
    int? hour,
    int? minute,
    int? events,
    int? minimumMarketProbability,
    String? market,
    bool? notifyChanges,
    String? systemMode,
  }) => GoalVdLineAutoCouponPreferences(
    requested: requested ?? this.requested,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    events: events ?? this.events,
    minimumMarketProbability:
        minimumMarketProbability ?? this.minimumMarketProbability,
    market: market ?? this.market,
    notifyChanges: notifyChanges ?? this.notifyChanges,
    systemMode: systemMode ?? this.systemMode,
  );

  Map<String, Object> toJson() => {
    'requested': requested,
    'hour': hour,
    'minute': minute,
    'events': events,
    'minimumMarketProbability': minimumMarketProbability,
    'market': market,
    'notifyChanges': notifyChanges,
    'systemMode': systemMode,
  };

  static GoalVdLineAutoCouponPreferences? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final requested = json['requested'];
    final hour = json['hour'];
    final minute = json['minute'];
    final events = json['events'];
    final minimum = json['minimumMarketProbability'];
    final market = json['market'];
    final notifyChanges = json['notifyChanges'];
    // Old saved settings are SINGLE, not silently upgraded to three.
    final systemMode = json['systemMode'] ?? single;
    if (requested is! bool ||
        hour is! int ||
        minute is! int ||
        events is! int ||
        minimum is! int ||
        market is! String ||
        notifyChanges is! bool ||
        systemMode is! String) {
      return null;
    }
    final result = GoalVdLineAutoCouponPreferences(
      requested: requested,
      hour: hour,
      minute: minute,
      events: events,
      minimumMarketProbability: minimum,
      market: market,
      notifyChanges: notifyChanges,
      systemMode: systemMode,
    );
    return result.isValid ? result : null;
  }
}

/// Un solo valore JSON: evita configurazioni parzialmente scritte.
class GoalVdLineAutoCouponPreferencesStore {
  static const storageKey = 'goalvdline_auto_coupon_preferences_v1';

  final Future<SharedPreferences> Function()? preferencesLoader;

  const GoalVdLineAutoCouponPreferencesStore({this.preferencesLoader});

  Future<SharedPreferences> _prefs() =>
      (preferencesLoader ?? SharedPreferences.getInstance)();

  Future<GoalVdLineAutoCouponPreferences> load() async {
    try {
      final raw = (await _prefs()).getString(storageKey);
      if (raw == null) return const GoalVdLineAutoCouponPreferences();
      return GoalVdLineAutoCouponPreferences.fromJson(jsonDecode(raw)) ??
          const GoalVdLineAutoCouponPreferences();
    } catch (_) {
      // Un archivio illeggibile non può mai abilitare una schedina automatica.
      return const GoalVdLineAutoCouponPreferences();
    }
  }

  Future<bool> save(GoalVdLineAutoCouponPreferences value) async {
    if (!value.isValid) return false;
    try {
      return await (await _prefs()).setString(
        storageKey,
        jsonEncode(value.toJson()),
      );
    } catch (_) {
      return false;
    }
  }
}
