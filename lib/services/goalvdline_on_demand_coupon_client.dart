import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'goalvdline_central_learning_mobile_sync.dart';
import 'goalvdline_mobile_token_vault.dart';

/// B47 opt-in transport. Importing this class never triggers remote work.
/// Local storage contains only a job/request id and public preferences;
/// mobile access credentials remain exclusively in the iOS Keychain.
class GoalVdLineOnDemandCouponClient {
  GoalVdLineOnDemandCouponClient({
    http.Client? client,
    Future<SharedPreferences> Function()? preferencesLoader,
    Random? random,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _random = random ?? Random.secure();

  final http.Client _client;
  final bool _ownsClient;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Random _random;

  static const _lastKey = 'goalvdline_on_demand_coupon_job_v1';
  static const _timeout = Duration(seconds: 12);
  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
  );

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static String _newRequestId(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<Map<String, dynamic>?> lastRequest() async {
    try {
      final raw = (await _preferencesLoader()).getString(_lastKey);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          !_uuid.hasMatch(data['requestId']?.toString() ?? '')) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<bool> available({
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    try {
      final origin = GoalVdLineCentralLearningMobileSync.serverOrigin(serverUrl);
      final req = http.Request('GET', origin.replace(path: '/learning/v1/status'))
        ..followRedirects = false;
      final streamed = await _client.send(req).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      if (response.statusCode != 200 || response.body.length > 16384) return false;
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> &&
          data['enabled'] == true &&
          data['mobileIngestEnabled'] == true &&
          data['onDemandCouponRequestsEnabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<GoalVdLineOnDemandStatus> submit({
    required String token,
    required int events,
    required int minimumMarketProbability,
    String market = 'MULTI',
    String systemMode = 'THREE_SAME_FIXTURES',
    int windowDays = 1,
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    if (!GoalVdLineMobileTokenVault.validToken(token)) {
      return const GoalVdLineOnDemandStatus.error('Token mobile non valido.');
    }
    if (events < 3 || events > 15 || minimumMarketProbability < 50 ||
        minimumMarketProbability > 90 || minimumMarketProbability % 5 != 0 ||
        !const ['MULTI', 'OVER_UNDER', 'GOAL_NOGOAL', '1X2'].contains(market) ||
        !const ['SINGLE', 'THREE_SAME_FIXTURES'].contains(systemMode) ||
        windowDays < 1 || windowDays > 3) {
      return const GoalVdLineOnDemandStatus.error('Impostazioni schedina non valide.');
    }
    final Uri origin;
    try {
      origin = GoalVdLineCentralLearningMobileSync.serverOrigin(serverUrl);
    } on FormatException {
      return const GoalVdLineOnDemandStatus.error('Indirizzo server non valido.');
    }
    final preferences = <String, Object>{
      'events': events,
      'minimumMarketProbability': minimumMarketProbability,
      'market': market,
      'systemMode': systemMode,
      'windowDays': windowDays,
    };
    final last = await lastRequest();
    final requestId = last != null &&
            last['preferences'] is Map &&
            jsonEncode(last['preferences']) == jsonEncode(preferences) &&
            last['jobId'] == null
        ? last['requestId'] as String
        : _newRequestId(_random);
    final store = await _preferencesLoader();
    // Save BEFORE sending: a timeout must retry with the same request ID.
    await store.setString(_lastKey, jsonEncode({
      'requestId': requestId, 'preferences': preferences,
    }));
    try {
      final req = http.Request(
        'POST', origin.replace(path: '/learning/v1/mobile/on-demand-coupon/jobs'),
      )..followRedirects = false;
      req.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      req.body = jsonEncode({'requestId': requestId, ...preferences});
      final streamed = await _client.send(req).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      if (response.statusCode == 503) {
        return const GoalVdLineOnDemandStatus.error('Elaborazione remota non attiva sul server.');
      }
      if (response.statusCode == 401) {
        return const GoalVdLineOnDemandStatus.error('Credenziale mobile scaduta.');
      }
      if (response.statusCode != 202 || response.body.length > 16384) {
        return GoalVdLineOnDemandStatus.error('Richiesta non accettata (HTTP ${response.statusCode}).');
      }
      final data = jsonDecode(response.body);
      final parsed = GoalVdLineOnDemandStatus.fromJson(data);
      if (parsed.jobId == null) {
        return const GoalVdLineOnDemandStatus.error('Conferma server non valida.');
      }
      await store.setString(_lastKey, jsonEncode({
        'requestId': requestId, 'jobId': parsed.jobId,
        'dayKey': parsed.dayKey, 'preferences': preferences,
      }));
      return parsed;
    } catch (_) {
      return const GoalVdLineOnDemandStatus.error(
        'Connessione interrotta: richiesta conservata per un nuovo tentativo.',
      );
    }
  }

  Future<GoalVdLineOnDemandStatus> fetch({
    required String token,
    required String jobId,
    String serverUrl = GoalVdLineCentralLearningMobileSync.defaultServerUrl,
  }) async {
    if (!GoalVdLineMobileTokenVault.validToken(token) || !_uuid.hasMatch(jobId)) {
      return const GoalVdLineOnDemandStatus.error('Credenziali o job non validi.');
    }
    try {
      final origin = GoalVdLineCentralLearningMobileSync.serverOrigin(serverUrl);
      final req = http.Request('GET', origin.replace(
        path: '/learning/v1/mobile/on-demand-coupon/jobs/$jobId',
      ))..followRedirects = false;
      req.headers.addAll({
        'Authorization': 'Bearer $token', 'Accept': 'application/json',
        'Cache-Control': 'no-store',
      });
      final streamed = await _client.send(req).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      if (response.statusCode == 404) {
        return const GoalVdLineOnDemandStatus.error('Richiesta non trovata.');
      }
      if (response.statusCode == 410) {
        return const GoalVdLineOnDemandStatus.error('Richiesta scaduta.');
      }
      if (![200, 202].contains(response.statusCode) || response.body.length > 65536) {
        return GoalVdLineOnDemandStatus.error('Verifica non riuscita (HTTP ${response.statusCode}).');
      }
      return GoalVdLineOnDemandStatus.fromJson(jsonDecode(response.body));
    } catch (_) {
      return const GoalVdLineOnDemandStatus.error('Server non raggiungibile.');
    }
  }
}

class GoalVdLineOnDemandStatus {
  const GoalVdLineOnDemandStatus({
    required this.status, this.jobId, this.dayKey, this.coupon,
    this.message = '',
  });
  const GoalVdLineOnDemandStatus.error(this.message)
      : status = 'error', jobId = null, dayKey = null, coupon = null;

  final String status;
  final String? jobId;
  final String? dayKey;
  final Map<String, dynamic>? coupon;
  final String message;

  bool get isReady => status == 'ready' && coupon != null;
  bool get isPending => status == 'queued' || status == 'running';

  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
  );

  static GoalVdLineOnDemandStatus fromJson(Object? data) {
    if (data is! Map<String, dynamic> || data['success'] != true ||
        data['jobId'] is! String ||
        !_uuid.hasMatch(data['jobId'] as String) ||
        data['dayKey'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data['dayKey'] as String) ||
        !const ['queued', 'running', 'ready', 'no_coupon', 'failed']
            .contains(data['status'])) {
      return const GoalVdLineOnDemandStatus.error('Stato remoto non verificabile.');
    }
    final status = data['status'] as String;
    final coupon = data['coupon'];
    if (status == 'ready' && (coupon is! Map<String, dynamic> ||
        coupon['events'] is! List ||
        (coupon['events'] as List).length < 3 ||
        (coupon['events'] as List).length > 15)) {
      return const GoalVdLineOnDemandStatus.error('Schedina remota non valida.');
    }
    return GoalVdLineOnDemandStatus(
      status: status,
      jobId: data['jobId'] as String,
      dayKey: data['dayKey'] as String,
      coupon: status == 'ready' ? coupon as Map<String, dynamic> : null,
    );
  }
}
