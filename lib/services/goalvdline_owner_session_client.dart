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
  }) => _submitVerifiedLogin(
    path: '/owner/v1/login', password: password, code: code,
    codeDigits: 6,
  );

  /// A password is still required. Mail is a secondary factor only when
  /// the owner's verified mailbox and sender are enabled on the backend.
  Future<GoalVdLineOwnerLoginOutcome> requestEmailRecovery({
    required String password,
  }) async {
    if (password.length < 16 || password.length > 256) {
      return const GoalVdLineOwnerLoginOutcome(
        false, 'Inserisci la tua password prima di richiedere il codice.',
      );
    }
    try {
      final request = http.Request('POST', _endpoint('/owner/v1/recovery/request'))
        ..followRedirects = false;
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      request.body = jsonEncode({'password':password});
      final stream = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(stream).timeout(_timeout);
      if (response.statusCode == 202) {
        return const GoalVdLineOwnerLoginOutcome(true,
          'Se la password è corretta, riceverai un codice via email. '
          'Controlla anche lo spam; scade dopo 10 minuti.');
      }
      return GoalVdLineOwnerLoginOutcome(false,
        response.statusCode == 503
          ? 'Recupero via email non ancora configurato sul server.'
          : response.statusCode == 429
            ? 'Limite richieste raggiunto. Riprova più tardi.'
            : 'Impossibile richiedere il codice di recupero.');
    } catch (_) {
      return const GoalVdLineOwnerLoginOutcome(false,
        'Server non raggiungibile per il recupero via email.');
    }
  }

  Future<GoalVdLineOwnerLoginOutcome> loginByEmailRecovery({
    required String password,
    required String code,
  }) => _submitVerifiedLogin(
    path: '/owner/v1/recovery/verify', password: password, code: code,
    codeDigits: 8,
  );

  Future<GoalVdLineOwnerLoginOutcome> _submitVerifiedLogin({
    required String path,
    required String password,
    required String code,
    required int codeDigits,
  }) async {
    if (password.length < 16 || password.length > 256 ||
        !RegExp('^\\d{$codeDigits}\\$').hasMatch(code)) {
      return GoalVdLineOwnerLoginOutcome(
        false, 'Inserisci password e codice valido di $codeDigits cifre.',
      );
    }
    try {
      final request = http.Request('POST', _endpoint(path))
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
            ? 'Account proprietario o recupero non ancora configurato sul server.'
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
