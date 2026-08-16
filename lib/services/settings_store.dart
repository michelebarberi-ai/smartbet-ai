import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const String _keyMinimumSmartScore = 'settings_minimum_smart_score';

  static const String _keyCouponSelections = 'settings_coupon_selections';

  static const String _keyOnlyPlayablePredictions =
      'settings_only_playable_predictions';

  static const String _keyAutoRemoveExpired = 'settings_auto_remove_expired';

  bool _initialized = false;

  int _minimumSmartScore = 65;

  int _couponSelections = 6;

  bool _onlyPlayablePredictions = false;

  bool _autoRemoveExpired = true;

  bool get initialized => _initialized;

  int get minimumSmartScore => _minimumSmartScore;

  int get couponSelections => _couponSelections;

  bool get onlyPlayablePredictions => _onlyPlayablePredictions;

  bool get autoRemoveExpired => _autoRemoveExpired;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      final prefs = SharedPreferencesAsync();

      _minimumSmartScore = await prefs.getInt(_keyMinimumSmartScore) ?? 65;

      _couponSelections = await prefs.getInt(_keyCouponSelections) ?? 6;

      _onlyPlayablePredictions =
          await prefs.getBool(_keyOnlyPlayablePredictions) ?? false;

      _autoRemoveExpired = await prefs.getBool(_keyAutoRemoveExpired) ?? true;
    } catch (e) {
      debugPrint('SettingsStore load error: $e');
    }

    _initialized = true;

    notifyListeners();
  }

  Future<void> setMinimumSmartScore(int value) async {
    _minimumSmartScore = value.clamp(50, 90);

    final prefs = SharedPreferencesAsync();

    await prefs.setInt(_keyMinimumSmartScore, _minimumSmartScore);

    notifyListeners();
  }

  Future<void> setCouponSelections(int value) async {
    _couponSelections = value.clamp(2, 6);

    final prefs = SharedPreferencesAsync();

    await prefs.setInt(_keyCouponSelections, _couponSelections);

    notifyListeners();
  }

  Future<void> setOnlyPlayablePredictions(bool value) async {
    _onlyPlayablePredictions = value;

    final prefs = SharedPreferencesAsync();

    await prefs.setBool(_keyOnlyPlayablePredictions, value);

    notifyListeners();
  }

  Future<void> setAutoRemoveExpired(bool value) async {
    _autoRemoveExpired = value;

    final prefs = SharedPreferencesAsync();

    await prefs.setBool(_keyAutoRemoveExpired, value);

    notifyListeners();
  }

  Future<void> resetDefaults() async {
    _minimumSmartScore = 65;
    _couponSelections = 6;
    _onlyPlayablePredictions = false;
    _autoRemoveExpired = true;

    final prefs = SharedPreferencesAsync();

    await prefs.setInt(_keyMinimumSmartScore, _minimumSmartScore);

    await prefs.setInt(_keyCouponSelections, _couponSelections);

    await prefs.setBool(_keyOnlyPlayablePredictions, _onlyPlayablePredictions);

    await prefs.setBool(_keyAutoRemoveExpired, _autoRemoveExpired);

    notifyListeners();
  }
}
