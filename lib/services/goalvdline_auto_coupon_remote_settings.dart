import 'dart:convert';

import 'package:http/http.dart' as http;

import 'goalvdline_auto_coupon_preferences.dart';
import 'goalvdline_central_learning_mobile_sync.dart';
import 'goalvdline_mobile_token_vault.dart';

/// B45 P7: invio ESPLICITO delle preferenze, non attiva scheduler o push.
class GoalVdLineAutoCouponRemoteSettings {
  GoalVdLineAutoCouponRemoteSettings({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<String> send({
    required GoalVdLineAutoCouponPreferences preferences,
    required String token,
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    if (!preferences.isValid) return 'Preferenze non valide.';
    if (!GoalVdLineMobileTokenVault.validToken(token)) {
      return 'Token mobile mancante: salvalo prima nel pannello del cervello centrale.';
    }
    final Uri origin;
    try {
      origin = GoalVdLineCentralLearningMobileSync.serverOrigin(serverUrl);
    } on FormatException {
      return 'Indirizzo del server non valido.';
    }
    final endpoint = origin.replace(
      path: '/learning/v1/mobile/auto-coupon/preferences',
    );
    try {
      final request = http.Request('POST', endpoint)..followRedirects = false;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      });
      request.body = jsonEncode({'preferences': preferences.toJson()});
      final stream = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(
        stream,
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode == 401)
        return 'Token non riconosciuto o scaduto.';
      if (response.statusCode == 503)
        return 'Funzione non ancora abilitata sul server.';
      if (response.statusCode != 200)
        return 'Server: errore HTTP ${response.statusCode}.';
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          decoded['success'] != true ||
          decoded['saved'] != true ||
          decoded['generationActive'] != false ||
          decoded['pushActive'] != false) {
        return 'Risposta server non verificabile: nessuna attivazione confermata.';
      }
      return 'Preferenze sincronizzate. Generazione automatica e notifiche non ancora attive.';
    } catch (_) {
      return 'Connessione interrotta. Preferenze locali conservate.';
    }
  }
}
