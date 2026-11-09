import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'goalvdline_central_learning_mobile_sync.dart';
import 'goalvdline_mobile_token_vault.dart';

/// B45 P12: opt-in registration only; NEVER sends a push by itself.
class GoalVdLineAutoCouponPushRegistration {
  GoalVdLineAutoCouponPushRegistration({
    http.Client? client,
    Future<String?> Function()? requestDeviceToken,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _requestDeviceToken = requestDeviceToken ?? _nativeDeviceToken;

  static const _channel = MethodChannel('goalvdline/push_registration');
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _requestDeviceToken;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static Future<String?> _nativeDeviceToken() async {
    if (!Platform.isIOS) return null;
    return _channel.invokeMethod<String>('requestDeviceToken');
  }

  Future<String> register({
    required String token,
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    if (!GoalVdLineMobileTokenVault.validToken(token))
      return 'Token mobile mancante.';
    try {
      final origin = GoalVdLineCentralLearningMobileSync.serverOrigin(
        serverUrl,
      );
      final available = await _client
          .get(
            origin.replace(path: '/learning/v1/status'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (available.statusCode != 200 ||
          jsonDecode(available.body)['autoCouponDeviceRegistrationEnabled'] !=
              true) {
        return 'Registrazione push non ancora abilitata sul server.';
      }
      final deviceToken = await _requestDeviceToken();
      if (deviceToken == null ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(deviceToken)) {
        return 'Permesso notifiche negato o dispositivo non registrato da iOS.';
      }
      final endpoint = origin.replace(
        path: '/learning/v1/mobile/auto-coupon/push/register',
      );
      final request = http.Request('POST', endpoint)..followRedirects = false;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      request.body = jsonEncode({'deviceToken': deviceToken.toLowerCase()});
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode == 401)
        return 'Token mobile scaduto o non riconosciuto.';
      if (response.statusCode == 409)
        return 'Salva e sincronizza prima le preferenze.';
      if (response.statusCode == 503)
        return 'Registrazione push non ancora abilitata.';
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map &&
            body['success'] == true &&
            body['registered'] == true &&
            body['pushActive'] == false) {
          return 'iPhone registrato. Notifiche ancora disattivate sul server.';
        }
      }
      return 'Registrazione non confermata dal server.';
    } on PlatformException {
      return 'iOS non ha autorizzato la registrazione push. Verifica i permessi.';
    } catch (_) {
      return 'Registrazione non riuscita. Riprova più tardi.';
    }
  }

  Future<String> unregister({
    required String token,
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    if (!GoalVdLineMobileTokenVault.validToken(token))
      return 'Token mobile mancante.';
    try {
      final origin = GoalVdLineCentralLearningMobileSync.serverOrigin(
        serverUrl,
      );
      final request = http.Request(
        'POST',
        origin.replace(path: '/learning/v1/mobile/auto-coupon/push/unregister'),
      )..followRedirects = false;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      request.body = '{}';
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map &&
            body['success'] == true &&
            body['registered'] == false &&
            body['pushActive'] == false) {
          return 'Registrazione notifiche rimossa dal server.';
        }
      }
      if (response.statusCode == 503)
        return 'Server push non ancora abilitato.';
      if (response.statusCode == 401)
        return 'Token mobile scaduto o non riconosciuto.';
      return 'Rimozione non confermata dal server.';
    } catch (_) {
      return 'Connessione non disponibile. La registrazione remota potrebbe rimanere attiva.';
    }
  }
}
