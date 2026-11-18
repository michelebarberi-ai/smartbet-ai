import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'goalvdline_central_learning_mobile_sync.dart';
import 'goalvdline_mobile_token_vault.dart';

class GoalVdLinePalinsestoRegistrationResult {
  const GoalVdLinePalinsestoRegistrationResult({
    required this.success,
    required this.pushActive,
    required this.message,
  });
  final bool success;
  final bool pushActive;
  final String message;
}

/// B73: independent, explicit APNs consent for the morning *calendar* digest.
/// Never enables or invokes scheduled automatic coupon generation.
class GoalVdLinePalinsestoDigestRegistration {
  GoalVdLinePalinsestoDigestRegistration({
    http.Client? client,
    Future<String?> Function()? readMobileToken,
    Future<String?> Function()? requestDeviceToken,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _readMobileToken = readMobileToken ?? GoalVdLineMobileTokenVault().read,
       _requestDeviceToken = requestDeviceToken ?? _nativeDeviceToken;

  static const _channel = MethodChannel('goalvdline/push_registration');
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _readMobileToken;
  final Future<String?> Function() _requestDeviceToken;

  static Future<String?> _nativeDeviceToken() async {
    if (!Platform.isIOS) return null;
    return _channel.invokeMethod<String>('requestDeviceToken');
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<GoalVdLinePalinsestoRegistrationResult> subscribe({
    required int hour,
    required int minute,
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return const GoalVdLinePalinsestoRegistrationResult(
        success: false, pushActive: false, message: 'Orario non valido.',
      );
    }
    try {
      final token = await _readMobileToken();
      if (token == null || !GoalVdLineMobileTokenVault.validToken(token)) {
        return const GoalVdLinePalinsestoRegistrationResult(
          success: false, pushActive: false,
          message: 'Token mobile non configurato. Preferenza salvata sul telefono.',
        );
      }
      final origin = GoalVdLineCentralLearningMobileSync.serverOrigin(serverUrl);
      final status = await _client.get(
        origin.replace(path: '/learning/v1/status'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 12));
      if (status.statusCode != 200 ||
          jsonDecode(status.body)['dailyPalinsestoRegistrationEnabled'] != true) {
        return const GoalVdLinePalinsestoRegistrationResult(
          success: false, pushActive: false,
          message: 'Notifiche mattutine non ancora abilitate sul server.',
        );
      }
      final deviceToken = await _requestDeviceToken();
      if (deviceToken == null ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(deviceToken)) {
        return const GoalVdLinePalinsestoRegistrationResult(
          success: false, pushActive: false,
          message: 'Autorizzazione notifiche iOS o token APNs mancante.',
        );
      }
      final req = http.Request('POST', origin.replace(
        path: '/learning/v1/mobile/palinsesto/subscribe',
      ))..followRedirects = false;
      req.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      req.body = jsonEncode({
        'deviceToken': deviceToken.toLowerCase(),
        'hour': hour,
        'minute': minute,
      });
      final response = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['registered'] == true &&
            body['success'] == true) {
          final enabled = body['pushActive'] == true;
          return GoalVdLinePalinsestoRegistrationResult(
            success: true, pushActive: enabled,
            message: enabled
                ? 'iPhone registrato per il riepilogo del mattino.'
                : 'iPhone registrato. Invio remoto non ancora attivo.',
          );
        }
      }
      return GoalVdLinePalinsestoRegistrationResult(
        success: false, pushActive: false,
        message: response.statusCode == 401
            ? 'Credenziale mobile scaduta: nuova registrazione richiesta.'
            : 'Registrazione remota non confermata.',
      );
    } on PlatformException {
      return const GoalVdLinePalinsestoRegistrationResult(
        success: false, pushActive: false,
        message: 'iOS non ha restituito un token APNs valido.',
      );
    } catch (_) {
      return const GoalVdLinePalinsestoRegistrationResult(
        success: false, pushActive: false,
        message: 'Connessione non disponibile: notifica non confermata.',
      );
    }
  }

  Future<GoalVdLinePalinsestoRegistrationResult> unsubscribe({
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    try {
      final token = await _readMobileToken();
      if (token == null || !GoalVdLineMobileTokenVault.validToken(token)) {
        return const GoalVdLinePalinsestoRegistrationResult(
          success: false, pushActive: false,
          message: 'Revoca remota non verificata: token mobile mancante.',
        );
      }
      final origin = GoalVdLineCentralLearningMobileSync.serverOrigin(serverUrl);
      final req = http.Request('POST', origin.replace(
        path: '/learning/v1/mobile/palinsesto/unsubscribe',
      ))..followRedirects = false;
      req.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      req.body = '{}';
      final response = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['registered'] == false &&
            body['success'] == true) {
          return const GoalVdLinePalinsestoRegistrationResult(
            success: true, pushActive: false,
            message: 'Riepilogo disattivato anche sul server.',
          );
        }
      }
      return const GoalVdLinePalinsestoRegistrationResult(
        success: false, pushActive: false,
        message: 'Disattivazione remota non confermata. Riprova connesso.',
      );
    } catch (_) {
      return const GoalVdLinePalinsestoRegistrationResult(
        success: false, pushActive: false,
        message: 'Disattivazione remota non confermata. Riprova connesso.',
      );
    }
  }
}
