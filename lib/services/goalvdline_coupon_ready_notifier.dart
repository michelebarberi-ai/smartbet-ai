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

  /// Diagnostica on-demand esplicita: mai simulare una schedina pronta.
  /// L'utente deve premere il pulsante di prova nelle impostazioni.
  Future<bool> sendTestNotification() async {
    if (!(await isEnabled())) return false;
    try {
      return await channel.invokeMethod<bool>('sendTestNotification') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Legge i permessi effettivi di iOS; la preferenza locale da sola
  /// non garantisce banner o avvisi sul blocco schermo.
  Future<GoalVdLineNotificationStatus?> notificationStatus() async {
    try {
      final map = await channel.invokeMapMethod<String, dynamic>(
        'getNotificationStatus',
      );
      if (map == null) return null;
      return GoalVdLineNotificationStatus(
        authorization: map['authorization']?.toString() ?? 'unknown',
        lockScreen: map['lockScreen'] == true,
        alerts: map['alerts'] == true,
        notificationCenter: map['notificationCenter'] == true,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Permette di bloccare il telefono dopo aver programmato la notifica.
  /// Non avvia analisi, job di background o push APNs.
  Future<bool> sendLockScreenTestNotification() async {
    if (!(await isEnabled())) return false;
    try {
      return await channel.invokeMethod<bool>(
            'sendLockScreenTestNotification',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
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

/// Impostazioni correnti restituite da iOS, indipendenti dalla scelta salvata.
class GoalVdLineNotificationStatus {
  const GoalVdLineNotificationStatus({
    required this.authorization,
    required this.lockScreen,
    required this.alerts,
    required this.notificationCenter,
  });

  final String authorization;
  final bool lockScreen;
  final bool alerts;
  final bool notificationCenter;

  bool get isAllowed =>
      authorization == 'authorized' || authorization == 'provisional';

  String get italianSummary {
    if (authorization == 'denied') {
      return 'Permesso iOS negato: abilita GoalVdLine in '
          'Impostazioni > Notifiche.';
    }
    if (!isAllowed) {
      return 'Permesso notifiche non attivo o non verificabile.';
    }
    if (!lockScreen) {
      return 'Schermo bloccato: avvisi non abilitati in iOS. '
          'Controlla Impostazioni > Notifiche > GoalVdLine.';
    }
    return 'Permesso iOS attivo e avvisi su schermo bloccato abilitati. '
        'Concentrazione e Riepilogo programmato possono ritardare '
        'la visualizzazione.';
  }
}
