import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/goalvdline_central_learning_mobile_sync.dart';
import 'package:smartbet_ai_new/services/goalvdline_central_learning_outbox.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  final timestamp = DateTime.utc(2026, 11, 4, 11);
  const origin = 'https://smartbet.example.test';
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ'; // 43 test chars

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GoalVdLineCentralLearningOutbox> queue({bool enabled = true}) async {
    final pref = await SharedPreferences.getInstance();
    final box = GoalVdLineCentralLearningOutbox(
      preferences: pref,
      clock: () => timestamp,
    );
    if (enabled) {
      await box.setConsent(true);
      final store = SmartBetAnalysisHistoryStore();
      final record = await store.registerAnalysis(
        engine: SmartBetAnalysisEngine.smartBet,
        source: SmartBetAnalysisSource.analysis,
        fixtureId: 9787,
        homeTeam: 'A',
        awayTeam: 'B',
        league: 'Test',
        country: 'Italia',
        matchDate: timestamp.add(const Duration(hours: 2)),
        market: 'OVER 2.5',
        probability: 0.73,
        recordedAt: timestamp,
      );
      expect(await box.captureIfEligible(record), true);
    }
    return box;
  }

  http.Response status({bool enabled = true}) => http.Response(
    jsonEncode({
      'enabled': enabled,
      'mobileIngestEnabled': enabled,
      'liveCalibration': false,
    }),
    200,
  );

  test('server GoalVdLine preconfigurato utilizza HTTPS e origine valida', () {
    final uri = GoalVdLineCentralLearningMobileSync.serverOrigin(
      GoalVdLineCentralLearningMobileSync.defaultServerUrl,
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'goalvdline-learning-api.onrender.com');
    expect(uri.path, isEmpty);
  });

  test('token e indirizzo non possono usare HTTP o credenziali in URL', () {
    expect(
      () => GoalVdLineCentralLearningMobileSync.serverOrigin(
        'http://example.com',
      ),
      throwsFormatException,
    );
    expect(
      () => GoalVdLineCentralLearningMobileSync.serverOrigin(
        'https://foo:pass@example.com',
      ),
      throwsFormatException,
    );
    expect(
      () =>
          GoalVdLineCentralLearningMobileSync.serverOrigin('https://foo/path'),
      throwsFormatException,
    );
    expect(
      GoalVdLineCentralLearningMobileSync.serverOrigin(origin).host,
      'smartbet.example.test',
    );
  });

  test('consenso OFF non richiama rete e non invia', () async {
    final box = await queue(enabled: false);
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return status();
    });
    final sync = GoalVdLineCentralLearningMobileSync(
      outbox: box,
      client: client,
    );
    final result = await sync.uploadOnce(baseUrl: origin, token: token);
    expect(result.confirmed, 0);
    expect(calls, 0);
    client.close();
  });

  test('server non abilitato: coda resta intatta', () async {
    final box = await queue();
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return status(enabled: false);
    });
    final sync = GoalVdLineCentralLearningMobileSync(
      outbox: box,
      client: client,
    );
    final result = await sync.uploadOnce(baseUrl: origin, token: token);
    expect(result.confirmed, 0);
    expect(box.pendingCount, 1);
    expect(paths, ['/learning/v1/status']);
    client.close();
  });

  test('conferma completa rimuove solo la previsione inviata', () async {
    final box = await queue();
    var postCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') return status();
      postCount++;
      expect(request.url.scheme, 'https');
      expect(request.url.path, '/learning/v1/mobile/predictions');
      expect(
        request.headers.entries
            .firstWhere((e) => e.key.toLowerCase() == 'authorization')
            .value,
        'Bearer $token',
      );
      final body = jsonDecode(request.body) as Map;
      expect(body.containsKey('historical'), false);
      expect(body.containsKey('clientId'), false);
      final predictions = body['predictions'] as List;
      expect(predictions, hasLength(1));
      expect((predictions.single as Map)['probability'], 0.73);
      return http.Response('{"success":true,"accepted":1,"duplicates":0}', 200);
    });
    final sync = GoalVdLineCentralLearningMobileSync(
      outbox: box,
      client: client,
    );
    final result = await sync.uploadOnce(baseUrl: origin, token: token);
    expect(result.confirmed, 1);
    expect(result.accepted, 1);
    expect(box.pendingCount, 0);
    expect(postCount, 1);
    final reloaded = GoalVdLineCentralLearningOutbox(
      preferences: await SharedPreferences.getInstance(),
      clock: () => timestamp,
    );
    expect(await reloaded.eligibleLocalDrafts(), isEmpty);
    client.close();
  });

  test(
    'duplicato server confermato rimuove da coda senza reinviare risultati',
    () async {
      final box = await queue();
      final client = MockClient(
        (request) async => request.method == 'GET'
            ? status()
            : http.Response(
                '{"success":true,"accepted":0,"duplicates":1}',
                200,
              ),
      );
      final sync = GoalVdLineCentralLearningMobileSync(
        outbox: box,
        client: client,
      );
      final result = await sync.uploadOnce(baseUrl: origin, token: token);
      expect(result.duplicates, 1);
      expect(box.pendingCount, 0);
      client.close();
    },
  );

  test('ack incompleto, HTTP 503 e rete: conservano la coda', () async {
    for (final reply in [
      http.Response('{"success":true,"accepted":0,"duplicates":0}', 200),
      http.Response('Service unavailable', 503),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final box = await queue();
      final client = MockClient(
        (request) async => request.method == 'GET' ? status() : reply,
      );
      final sync = GoalVdLineCentralLearningMobileSync(
        outbox: box,
        client: client,
      );
      final result = await sync.uploadOnce(baseUrl: origin, token: token);
      expect(result.confirmed, 0);
      expect(box.pendingCount, 1);
      client.close();
    }
  });

  test(
    'reindirizzamenti HTTP non inoltrano il token e non svuotano la coda',
    () async {
      final box = await queue();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.followRedirects, false);
        if (request.method == 'GET') return status();
        return http.Response(
          'Redirect',
          307,
          headers: {'location': 'https://server-esterno.example/collect'},
        );
      });
      final sync = GoalVdLineCentralLearningMobileSync(
        outbox: box,
        client: client,
      );
      final result = await sync.uploadOnce(baseUrl: origin, token: token);
      expect(result.confirmed, 0);
      expect(calls, 2);
      expect(box.pendingCount, 1);
      client.close();
    },
  );

  test('cancellazione remota richiede risposta valida', () async {
    final box = await queue();
    final client = MockClient((request) async {
      expect(request.url.path, '/learning/v1/mobile/erase');
      expect(
        request.headers.entries
            .firstWhere((e) => e.key.toLowerCase() == 'authorization')
            .value,
        'Bearer $token',
      );
      return http.Response('{"success":true,"deleted":2}', 200);
    });
    final sync = GoalVdLineCentralLearningMobileSync(
      outbox: box,
      client: client,
    );
    final result = await sync.eraseRemote(baseUrl: origin, token: token);
    expect(result.success, true);
    expect(box.pendingCount, 1); // il service non modifica archivi locali
    client.close();
  });

  test('mercati non supportati restano esclusi dal lotto mobile', () {
    expect(
      GoalVdLineCentralLearningMobileSync.isSupportedMarket('OVER 2.5'),
      true,
    );
    expect(
      GoalVdLineCentralLearningMobileSync.isSupportedMarket(
        'HCP ASIA CASA -0.5',
      ),
      false,
    );
    expect(
      GoalVdLineCentralLearningMobileSync.isSupportedMarket('OVER 2.0'),
      false,
    );
    expect(GoalVdLineCentralLearningMobileSync.isSupportedMarket('1X'), true);
    expect(
      GoalVdLineCentralLearningMobileSync.isSupportedMarket('O1.5 + GOAL'),
      true,
    );
  });
}
