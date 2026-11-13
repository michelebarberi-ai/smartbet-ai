import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Solo notifiche LOCALI per schedine avviate dall'utente sull'iPhone.
/// Nessun APNs, cron, job remoto o generazione in background.
class GoalVdLineCouponReadyNotifier {
  const GoalVdLineCouponReadyNotifier();

  static const storageKey = 'goalvdline_coupon_ready_local_v1';
  static const channel = MethodChannel('goalvdline/local_coupon_notifications');

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(storageKey) ?? false;
  }

  /// Richiede consenso iOS solo dopo un'azione esplicita dell'utente.
  /// Piattaforme senza handler: la notifica di sistema resta disattiva.
  Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.setBool(storageKey, false);
      return false;
    }
    try {
      final granted = await channel.invokeMethod<bool>('requestPermission') ?? false;
      await prefs.setBool(storageKey, granted);
      return granted;
    } on PlatformException {
      await prefs.setBool(storageKey, false);
      return false;
    } on MissingPluginException {
      await prefs.setBool(storageKey, false);
      return false;
    }
  }

  /// Notifica SOLO un risultato già completato (mai una schedina vuota).
  /// L'errore di notifica non deve compromettere i pronostici.
  Future<bool> notifyReady({
    required int coupons,
    required int fixturesInPrimary,
  }) async {
    if (coupons < 1 || fixturesInPrimary < 1 || !(await isEnabled())) {
      return false;
    }
    try {
      return await channel.invokeMethod<bool>('notifyReady', {
            'coupons': coupons,
            'fixtures': fixturesInPrimary,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
