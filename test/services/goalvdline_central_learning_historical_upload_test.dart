import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/goalvdline_central_learning_mobile_sync.dart';
import 'package:smartbet_ai_new/services/goalvdline_historical_learning_review.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  const url = 'https://learning.example.test';
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GoalVdLineHistoricalLearningReview> sample() async {
    final prefs = await SharedPreferences.getInstance();
    final review = GoalVdLineHistoricalLearningReview(
      preferences: prefs,
      clock: () => DateTime.utc(2026, 11, 8),
    );
    final history = SmartBetAnalysisHistoryStore();
    await history.registerAnalysis(
      engine: SmartBetAnalysisEngine.smartBet,
      source: SmartBetAnalysisSource.analysis,
      fixtureId: 99771,
      homeTeam: 'A',
      awayTeam: 'B',
      league: 'Test',
      country: 'Italia',
      matchDate: DateTime.utc(2026, 10, 30),
      market: 'OVER 2.5',
      probability: 0.72,
      recordedAt: DateTime.utc(2026, 10, 29),
    );
    await review.prepareFromHistory(history.records);
    expect(review.preparedCount, 1);
    return review;
  }

  test('storico: consenso locale mancante, zero chiamate di rete', () async {
    final review = GoalVdLineHistoricalLearningReview(
      preferences: await SharedPreferences.getInstance(),
    );
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    final sync = GoalVdLineCentralLearningMobileSync(client: client);
    final result = await sync.uploadHistorical(
      baseUrl: url,
      token: token,
      history: review,
    );
    expect(result.completed, false);
    expect(calls, 0);
    client.close();
  });

  test(
    'storico: endpoint diverso, copia locale intatta, risposta verificata',
    () async {
      final review = await sample();
      final paths = <String>[];
      final client = MockClient((req) async {
        paths.add(req.url.path);
        expect(req.followRedirects, false);
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'retrospectiveIngestEnabled': true,
              'liveCalibration': false,
            }),
            200,
          );
        }
        expect(req.url.path, '/learning/v1/mobile/retrospective');
        final data = jsonDecode(req.body) as Map<String, dynamic>;
        expect(data.containsKey('clientId'), false);
        expect(data.containsKey('predictions'), false);
        expect(
          (data['snapshots'] as List).single['kind'],
          'retrospective_unverified_v1',
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'kind': 'retrospective_unverified_v1',
            'appliesToLivePredictions': false,
            'accepted': 1,
            'duplicates': 0,
          }),
          200,
        );
      });
      final sync = GoalVdLineCentralLearningMobileSync(client: client);
      final result = await sync.uploadHistorical(
        baseUrl: url,
        token: token,
        history: review,
      );
      expect(result.completed, true);
      expect(result.accepted, 1);
      expect(review.preparedCount, 1);
      expect(paths, [
        '/learning/v1/status',
        '/learning/v1/mobile/retrospective',
      ]);
      client.close();
    },
  );

  test('storico: flag server spento, nessun dato inviato', () async {
    final review = await sample();
    var posts = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') posts++;
      return http.Response(
        jsonEncode({
          'retrospectiveIngestEnabled': false,
          'liveCalibration': false,
        }),
        200,
      );
    });
    final sync = GoalVdLineCentralLearningMobileSync(client: client);
    final result = await sync.uploadHistorical(
      baseUrl: url,
      token: token,
      history: review,
    );
    expect(result.completed, false);
    expect(posts, 0);
    expect(review.preparedCount, 1);
    client.close();
  });
}
