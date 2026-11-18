import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/goalvdline_central_learning_mobile_sync.dart';
import 'package:smartbet_ai_new/services/goalvdline_central_learning_outbox.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18, 10);
  const origin = 'https://smartbet.example.test';
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GoalVdLineCentralLearningOutbox> outbox({
    bool consent = true,
    bool includeLegacy = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final box = GoalVdLineCentralLearningOutbox(
      preferences: prefs,
      clock: () => now,
    );
    if (!consent) return box;
    await box.setConsent(true);
    final store = SmartBetAnalysisHistoryStore();
    final records = await store.registerMarketBundle(
      engine: SmartBetAnalysisEngine.simulator,
      source: SmartBetAnalysisSource.aiCoupon,
      fixtureId: 125,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      country: 'Italia',
      league: 'Serie A',
      matchDate: now.add(const Duration(hours: 4)),
      markets: const {
        '1': 0.55,
        'X': 0.25,
        '2': 0.20,
        'GOAL': 0.70,
        'NO GOAL': 0.30,
        'OVER 2.5': 0.62,
        'UNDER 2.5': 0.38,
      },
      classification: 'SIMULATOR_XG_FROM_SMARTBET',
      recordedAt: now,
    );
    expect(await box.captureBatchIfEligible(records), hasLength(7));
    if (includeLegacy) {
      final normal = await store.registerAnalysis(
        engine: SmartBetAnalysisEngine.smartBet,
        source: SmartBetAnalysisSource.aiCoupon,
        fixtureId: 126,
        homeTeam: 'A',
        awayTeam: 'B',
        country: 'Italia',
        league: 'Serie A',
        matchDate: now.add(const Duration(hours: 4)),
        market: 'GOAL',
        probability: 0.75,
        recordedAt: now,
      );
      expect(await box.captureIfEligible(normal), isTrue);
    }
    return box;
  }

  http.Response capability({bool simulator = false}) => http.Response(
    jsonEncode({
      'enabled': true,
      'mobileIngestEnabled': true,
      'simulatorIngestEnabled': simulator,
      'liveCalibration': false,
    }),
    200,
  );

  test('B66: explicit consent is required before capturing simulator', () async {
    final box = await outbox(consent: false);
    expect(box.consentGranted, false);
    expect(box.pendingDrafts, isEmpty);
    expect((await box.captureBatchIfEligible([])), isEmpty);
  });

  test('B66: source and original forecast persist without duplication', () async {
    final box = await outbox();
    final first = box.pendingDrafts;
    expect(first, hasLength(7));
    expect(first.every((p) =>
        p.engine == 'simulator' && p.inputSource == 'smartBet'), isTrue);
    expect(first.map((p) => p.key).toSet(), hasLength(7));
    final reloaded = GoalVdLineCentralLearningOutbox(
      preferences: await SharedPreferences.getInstance(),
      clock: () => now,
    );
    final saved = await reloaded.eligibleLocalDrafts();
    expect(saved, hasLength(7));
    expect(saved.singleWhere((p) => p.market == 'GOAL').probability, 0.7);
    expect(saved.every((p) => p.inputSource == 'smartBet'), isTrue);
    expect(GoalVdLineLearningDraft.fromJson({
      'fixtureId': 2, 'engine':'simulator', 'market':'GOAL',
      'probability':0.7,
      'firstSeenAt':now.toIso8601String(),
      'kickoffAt':now.add(const Duration(hours:2)).toIso8601String(),
    }), isNull);
  });

  test('B66: capability OFF preserves all simulator drafts and makes no POST',
      () async {
    final box = await outbox();
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add('${request.method} ${request.url.path}');
      return capability();
    });
    final sync = GoalVdLineCentralLearningMobileSync(outbox: box, client: client);
    final result = await sync.uploadOnce(baseUrl: origin, token: token);
    expect(result.confirmed, 0);
    expect(result.message, contains('Simulatore'));
    expect(box.pendingCount, 7);
    expect(paths, ['GET /learning/v1/status']);
    sync.dispose();
    client.close();
  });

  test('B66: legacy upload works while simulator remains server-disabled',
      () async {
    final box = await outbox(includeLegacy: true);
    final client = MockClient((request) async {
      if (request.method == 'GET') return capability();
      final payload = jsonDecode(request.body) as Map;
      final predictions = payload['predictions'] as List;
      expect(predictions, hasLength(1));
      expect((predictions.single as Map)['engine'], 'smartBet');
      expect((predictions.single as Map).containsKey('inputSource'), isFalse);
      return http.Response('{"success":true,"accepted":1,"duplicates":0}', 200);
    });
    final sync = GoalVdLineCentralLearningMobileSync(outbox: box, client: client);
    final result = await sync.uploadOnce(baseUrl: origin, token: token);
    expect(result.confirmed, 1);
    expect(box.pendingCount, 7);
    sync.dispose();
    client.close();
  });

  test('B66: capability ON uploads seven forecasts with source and no result',
      () async {
    final box = await outbox();
    var posted = false;
    final client = MockClient((request) async {
      expect(request.followRedirects, false);
      if (request.method == 'GET') return capability(simulator: true);
      posted = true;
      expect(request.url.path, '/learning/v1/mobile/predictions');
      expect(request.headers['authorization'] ?? request.headers['Authorization'],
          'Bearer $token');
      final payload = jsonDecode(request.body) as Map;
      expect(payload.containsKey('clientId'), isFalse);
      expect(payload.containsKey('results'), isFalse);
      final predictions = payload['predictions'] as List;
      expect(predictions, hasLength(7));
      expect(predictions.every((p) => (p as Map)['engine'] == 'simulator' &&
          p['inputSource'] == 'smartBet' && !p.containsKey('firstSeenAt') &&
          !p.containsKey('actualHomeGoals')), isTrue);
      return http.Response('{"success":true,"accepted":7,"duplicates":0}', 200);
    });
    final sync = GoalVdLineCentralLearningMobileSync(outbox: box, client: client);
    final result = await sync.uploadOnce(baseUrl: origin, token: token);
    expect(posted, isTrue);
    expect(result.confirmed, 7);
    expect(box.pendingCount, 0);
    sync.dispose();
    client.close();
  });

  test('B66: mismatched server ACK retains local queue, even when enabled',
      () async {
    final box = await outbox();
    final client = MockClient((request) async =>
        request.method == 'GET'
            ? capability(simulator: true)
            : http.Response('{"success":true,"accepted":5,"duplicates":0}', 200));
    final sync = GoalVdLineCentralLearningMobileSync(outbox: box, client: client);
    final result = await sync.uploadOnce(baseUrl: origin, token: token);
    expect(result.confirmed, 0);
    expect(box.pendingCount, 7);
    sync.dispose();
    client.close();
  });

  test('B66: explicit opt-out clears captured simulator drafts', () async {
    final box = await outbox();
    await box.setConsent(false);
    expect(box.consentGranted, isFalse);
    final reload = GoalVdLineCentralLearningOutbox(
      preferences: await SharedPreferences.getInstance(),
      clock: () => now,
    );
    expect(await reload.eligibleLocalDrafts(), isEmpty);
  });
}
