import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_on_demand_coupon_client.dart';

const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const jobId = '11111111-1111-4111-8111-111111111111';
const day = '2026-11-13';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('B47: remote generation is gated by explicit server status', () async {
    final client = GoalVdLineOnDemandCouponClient(
      client: MockClient((request) async {
        expect(request.url.path, '/learning/v1/status');
        return http.Response(jsonEncode({
          'enabled': true,
          'mobileIngestEnabled': true,
          'onDemandCouponRequestsEnabled': false,
        }), 200);
      }),
    );
    expect(await client.available(), false);
  });

  test('B47: submit stores job id and reopens via GET without duplicate POST',
      () async {
    var postCount = 0;
    var readCount = 0;
    final client = GoalVdLineOnDemandCouponClient(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          postCount++;
          expect(request.url.path,
              '/learning/v1/mobile/on-demand-coupon/jobs');
          expect(request.headers['authorization'], 'Bearer $token');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['events'], 5);
          expect(payload['systemMode'], 'THREE_SAME_FIXTURES');
          expect(payload.containsKey('clientId'), false);
          expect(payload.containsKey('adminToken'), false);
          return http.Response(jsonEncode({
            'success': true, 'jobId': jobId,
            'dayKey': day, 'status': 'queued',
          }), 202);
        }
        readCount++;
        expect(request.method, 'GET');
        expect(request.url.path,
            '/learning/v1/mobile/on-demand-coupon/jobs/$jobId');
        return http.Response(jsonEncode({
          'success': true, 'jobId': jobId,
          'dayKey': day, 'status': 'running',
        }), 202);
      }),
    );

    final first = await client.submit(
      token: token, events: 5, minimumMarketProbability: 65,
    );
    expect(first.isPending, true);
    expect(first.jobId, jobId);
    expect((await client.lastRequest())?['jobId'], jobId);

    final resumed = await client.submit(
      token: token, events: 5, minimumMarketProbability: 65,
    );
    expect(resumed.status, 'running');
    expect(postCount, 1);
    expect(readCount, 1);
  });

  test('B47: invalid token and weak settings never contact the server',
      () async {
    var calls = 0;
    final client = GoalVdLineOnDemandCouponClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    final tokenError = await client.submit(
      token: 'not-a-token', events: 5, minimumMarketProbability: 65,
    );
    final weak = await client.submit(
      token: token, events: 5, minimumMarketProbability: 10,
    );
    expect(tokenError.status, 'error');
    expect(weak.status, 'error');
    expect(calls, 0);
  });

  test('B47: successful remote result requires valid verified structure', () {
    const response = {
      'success': true, 'jobId': jobId,
      'dayKey': day, 'status': 'ready',
    };
    final invalid = GoalVdLineOnDemandStatus.fromJson(response);
    expect(invalid.isReady, false);
    final valid = GoalVdLineOnDemandStatus.fromJson({
      ...response,
      'coupon': {
        'events': [
          for (var i = 1; i <= 3; i++)
            {
              'fixtureId': i, 'market': 'OVER 1.5',
              'marketProbability': 85, 'odds': 1.35,
              'kickoffAt': '2026-11-13T18:00:00Z',
            },
        ],
      },
    });
    expect(valid.isReady, true);
  });
}
