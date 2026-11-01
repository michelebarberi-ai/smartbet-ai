import 'package:shared_preferences/shared_preferences.dart';

/// Preferenza sperimentale locale, mai sincronizzata con il backend.
/// OFF in assenza del valore o se la lettura fallisce.
class SmartBetDeviceLearningPreferences {
  static const String storageKey = 'smartbet_local_live_learning_opt_in_v1';

  final Future<SharedPreferences> Function()? preferencesLoader;

  const SmartBetDeviceLearningPreferences({this.preferencesLoader});

  Future<SharedPreferences> _getPreferences() =>
      (preferencesLoader ?? SharedPreferences.getInstance)();

  Future<bool> loadEnabled() async {
    try {
      return (await _getPreferences()).getBool(storageKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// Restituisce true solo se la preferenza e' stata scritta davvero.
  Future<bool> saveEnabled(bool enabled) async {
    try {
      return await (await _getPreferences()).setBool(storageKey, enabled);
    } catch (_) {
      return false;
    }
  }
}
