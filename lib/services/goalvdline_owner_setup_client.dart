import 'dart:convert';

import 'package:http/http.dart' as http;

import 'goalvdline_central_learning_mobile_sync.dart';

/// First-time enrollment only; no admin-token or password is baked in the app.
/// Enrollment ticket is kept in memory by the setup screen and never written
/// to a persistent log, analytics event or preference.
class GoalVdLineOwnerSetupResponse {
  const GoalVdLineOwnerSetupResponse({
    required this.success,
    required this.message,
    this.ready = false,
    this.activated = false,
    this.ticket,
    this.totpManualKey,
  });

  final bool success;
  final String message;
  final bool ready;
  final bool activated;
  final String? ticket;
  final String? totpManualKey;
}

class GoalVdLineOwnerSetupClient {
  GoalVdLineOwnerSetupClient({
    http.Client? client,
    String baseUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _origin = GoalVdLineCentralLearningMobileSync.serverOrigin(baseUrl);

  static const Duration _timeout = Duration(seconds: 12);
  // The free Render service may need extra time to wake up.
  // A read-only status request can be retried safely; enrollment POSTs cannot.
  static const Duration _readinessTimeout = Duration(seconds: 35);
  final http.Client _client;
  final bool _ownsClient;
  final Uri _origin;
  static final _ticketFormat = RegExp(r'^[A-Za-z0-9_-]{43}$');

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<GoalVdLineOwnerSetupResponse> status() async {
    // Status is GET-only: retry one transient transport failure without
    // ever sending a duplicate activation email or changing owner state.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = http.Request('GET', _url('/owner/v1/setup/status'))
          ..followRedirects = false;
        final sent = await _client.send(request).timeout(_readinessTimeout);
        final response = await http.Response.fromStream(sent)
            .timeout(_readinessTimeout);
        final data = _readMap(response);
        if (response.statusCode != 200 || data['ready'] != true) {
          return const GoalVdLineOwnerSetupResponse(
            success: false,
            message: 'Attivazione protetta non ancora configurata sul server.',
          );
        }
        if (data['activated'] == true) {
          return const GoalVdLineOwnerSetupResponse(
            success: true,
            ready: true,
            activated: true,
            message: 'L’account proprietario è già attivato: usa il login.',
          );
        }
        return const GoalVdLineOwnerSetupResponse(
          success: true,
          ready: true,
          message: 'Puoi iniziare: il codice verrà inviato alla casella '
              'proprietario già autorizzata sul server.',
        );
      } catch (_) {
        // Only a GET transport failure is retried. Never retry 503 (the
        // backend may actually be disabled) or any enrollment POST.
        if (attempt == 1) {
          return const GoalVdLineOwnerSetupResponse(
            success: false,
            message: 'Il server non risponde ancora. Potrebbe riattivarsi '
                'dopo un periodo di inattività: riprova la verifica.',
          );
        }
      }
    }
    return const GoalVdLineOwnerSetupResponse(
      success: false,
      message: 'Impossibile verificare lo stato del server.',
    );
  }

  Future<GoalVdLineOwnerSetupResponse> requestCode() async {
    final result = await _post('/owner/v1/setup/request', {});
    if (result.status == 202) {
      return const GoalVdLineOwnerSetupResponse(
        success: true,
        message: 'Codice richiesto. Controlla la tua email: '
            'il codice di 8 cifre scade dopo 10 minuti.',
      );
    }
    if (result.status == 0) {
      return const GoalVdLineOwnerSetupResponse(
        success: false,
        message: 'Invio non confermato dal server. Controlla prima la '
            'casella email: il codice potrebbe essere già stato inviato. '
            'Non richiedere subito un altro codice.',
      );
    }
    return _failure(result.status);
  }

  Future<GoalVdLineOwnerSetupResponse> verifyEmail(String code) async {
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      return const GoalVdLineOwnerSetupResponse(
        success: false, message: 'Inserisci le 8 cifre ricevute via email.',
      );
    }
    final result = await _post('/owner/v1/setup/verify', {'code': code});
    final ticket = result.data['ticket'];
    if (result.status == 200 && result.data['success'] == true &&
        ticket is String && _ticketFormat.hasMatch(ticket)) {
      return GoalVdLineOwnerSetupResponse(
        success: true,
        ticket: ticket,
        message: 'Email verificata. Ora abbina Authenticator.',
      );
    }
    return _failure(result.status);
  }

  Future<GoalVdLineOwnerSetupResponse> startAuthenticator(String ticket) async {
    if (!_ticketFormat.hasMatch(ticket)) return _failure(401);
    final result = await _post(
      '/owner/v1/setup/totp/start', {},
      bearer: ticket,
    );
    final secret = result.data['manualKey'];
    if (result.status == 200 && result.data['success'] == true &&
        secret is String &&
        RegExp(r'^[A-Z2-7]{32}$').hasMatch(secret)) {
      return GoalVdLineOwnerSetupResponse(
        success: true,
        totpManualKey: secret,
        message: 'Aggiungi manualmente questa chiave '
            'nell’app Authenticator. Poi inserisci il codice a 6 cifre.',
      );
    }
    return _failure(result.status);
  }

  Future<GoalVdLineOwnerSetupResponse> finish({
    required String ticket,
    required String password,
    required String code,
  }) async {
    if (!_ticketFormat.hasMatch(ticket) || password.length < 16 ||
        password.length > 256 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      return const GoalVdLineOwnerSetupResponse(
        success: false,
        message: 'Servono password di almeno 16 caratteri '
            'e codice Authenticator di 6 cifre.',
      );
    }
    final result = await _post(
      '/owner/v1/setup/finish',
      {'password': password, 'code': code},
      bearer: ticket,
    );
    if (result.status == 200 && result.data['activated'] == true) {
      return const GoalVdLineOwnerSetupResponse(
        success: true,
        activated: true,
        message: 'Account attivato. Torna al login e usa '
            'la nuova password con il prossimo codice Authenticator.',
      );
    }
    return _failure(result.status);
  }

  Uri _url(String path) => _origin.replace(
    path: path, query: null, fragment: null,
  );

  Future<({int status, Map<String, dynamic> data})> _post(
    String path,
    Map<String, dynamic> data, {
    String? bearer,
  }) async {
    try {
      final req = http.Request('POST', _url(path))
        ..followRedirects = false;
      req.headers['Content-Type'] = 'application/json';
      req.headers['Accept'] = 'application/json';
      if (bearer != null) req.headers['Authorization'] = 'Bearer $bearer';
      req.body = jsonEncode(data);
      // Allow the initial email request to survive a server cold start.
      // Do not auto-retry: the server may have already issued the OTP.
      final timeout = path == '/owner/v1/setup/request'
          ? _readinessTimeout
          : _timeout;
      final sent = await _client.send(req).timeout(timeout);
      final res = await http.Response.fromStream(sent).timeout(timeout);
      return (status: res.statusCode, data: _readMap(res));
    } catch (_) {
      return (status: 0, data: <String, dynamic>{});
    }
  }

  static Map<String, dynamic> _readMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic>
          ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static GoalVdLineOwnerSetupResponse _failure(int status) {
    if (status == 409) {
      return const GoalVdLineOwnerSetupResponse(
        success: false, activated: true,
        message: 'Account già attivato: utilizza il login proprietario.',
      );
    }
    if (status == 429) {
      return const GoalVdLineOwnerSetupResponse(
        success: false, message: 'Troppi tentativi. Riprova più tardi.',
      );
    }
    if (status == 503) {
      return const GoalVdLineOwnerSetupResponse(
        success: false,
        message: 'Il server non ha ancora completato la configurazione '
            'sicura dell’account e della casella email.',
      );
    }
    return const GoalVdLineOwnerSetupResponse(
      success: false,
      message: 'Codice non valido, scaduto o server non raggiungibile.',
    );
  }
}
