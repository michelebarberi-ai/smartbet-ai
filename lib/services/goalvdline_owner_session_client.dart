import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'goalvdline_central_learning_mobile_sync.dart';

/// B59 — the OWNER login session is NOT the historical LEARNING_ADMIN_TOKEN
/// and is NOT a device contribution token. It has a separate Keychain entry.
class GoalVdLineOwnerSessionVault {
  GoalVdLineOwnerSessionVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'goalvdline_owner_login_session_v1';
  static final _tokenFormat = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static bool validToken(String value) => _tokenFormat.hasMatch(value);

  Future<String?> read() async {
    final token = await _storage.read(key: _key);
    if (token == null) return null;
    if (!validToken(token)) {
      await delete();
      return null;
    }
    return token;
  }

  Future<void> save(String token) async {
    if (!validToken(token)) throw const FormatException('Sessione non valida');
    await _storage.write(
      key: _key,
      value: token,
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.unlocked,
        synchronizable: false,
      ),
    );
  }

  Future<void> delete() => _storage.delete(key: _key);
}

class GoalVdLineOwnerLoginOutcome {
  final bool success;
  final String message;
  const GoalVdLineOwnerLoginOutcome(this.success, this.message);
}

/// Client with redirects disabled: credentials and bearer MUST NOT be
/// forwarded to other hosts. Always talks directly to HTTPS learning backend.
class GoalVdLineOwnerSessionClient {
  GoalVdLineOwnerSessionClient({
    http.Client? client,
    GoalVdLineOwnerSessionVault? vault,
    String baseUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _vault = vault ?? GoalVdLineOwnerSessionVault(),
        _origin = GoalVdLineCentralLearningMobileSync.serverOrigin(baseUrl);

  static const _timeout = Duration(seconds: 12);
  final http.Client _client;
  final bool _ownsClient;
  final GoalVdLineOwnerSessionVault _vault;
  final Uri _origin;

  Uri _endpoint(String path) =>
      _origin.replace(path: path, query: null, fragment: null);

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<GoalVdLineOwnerLoginOutcome> login({
    required String password,
    required String code,
  }) async {
    if (password.length < 16 || password.length > 256 ||
        !RegExp(r'^\d{6}$').hasMatch(code)) {
      return const GoalVdLineOwnerLoginOutcome(
        false, 'Inserisci password e codice Authenticator valido di 6 cifre.',
      );
    }
    try {
      final request = http.Request('POST', _endpoint('/owner/v1/login'))
        ..followRedirects = false;
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      request.body = jsonEncode({'password': password, 'code': code});
      final stream = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(stream).timeout(_timeout);
      if (response.statusCode != 200) {
        return GoalVdLineOwnerLoginOutcome(false,
          response.statusCode == 503
            ? 'Account proprietario non ancora configurato sul server.'
            : response.statusCode == 429
              ? 'Troppi tentativi: riprova dopo il blocco di sicurezza.'
              : 'Accesso non autorizzato.');
      }
      final data = jsonDecode(response.body);
      if (data is! Map || data['success'] != true ||
          data['scope'] != 'owner-staging-login-only' ||
          data['expiresInSeconds'] is! int ||
          data['expiresInSeconds'] <= 0 ||
          data['expiresInSeconds'] > 900 ||
          data['token'] is! String ||
          !GoalVdLineOwnerSessionVault.validToken(data['token'])) {
        return const GoalVdLineOwnerLoginOutcome(
          false, 'La risposta di autenticazione non è valida.',
        );
      }
      await _vault.save(data['token']);
      return const GoalVdLineOwnerLoginOutcome(true, 'Accesso verificato.');
    } catch (_) {
      return const GoalVdLineOwnerLoginOutcome(
        false, 'Impossibile verificare l’accesso sul server.',
      );
    }
  }

  /// No trust in local Keychain presence without a server-side session check.
  Future<bool> hasValidSession() async {
    try {
      final token = await _vault.read();
      if (token == null) return false;
      final request = http.Request('GET', _endpoint('/owner/v1/session'))
        ..followRedirects = false;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      final stream = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(stream).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map && data['success'] == true &&
            data['active'] == true;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        await _vault.delete();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    try {
      final token = await _vault.read();
      if (token == null) return;
      final request = http.Request('POST', _endpoint('/owner/v1/logout'))
        ..followRedirects = false;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      await _client.send(request).timeout(_timeout);
    } catch (_) {
      // Network errors still clear this device's session.
    } finally {
      await _vault.delete();
    }
  }
}
