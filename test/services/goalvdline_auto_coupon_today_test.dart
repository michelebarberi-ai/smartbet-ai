import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_today.dart';

void main() {
  const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  Map<String, Object?> readyBody([List<Map<String, Object?>>? events]) => {
    'success': true,
    'dayKey': '2026-11-09',
    'status': 'ready',
    'coupon': {
      'events':
          events ??
          [
            for (var i = 1; i <= 3; i++)
              {
                'fixtureId': i,
                'market': 'OVER_UNDER',
                'marketProbability': 70.0,
                'kickoffAt': '2026-11-09T19:00:00Z',
                'odds': 1.80,
              },
          ],
    },
  };

  test('P20 shows exactly three verified same-fixture coupons', () async {
    final main = ((readyBody()['coupon'] as Map)['events'] as List)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    final alternative1 = main.map((e) => Map<String, Object?>.from(e)).toList();
    final alternative2 = main.map((e) => Map<String, Object?>.from(e)).toList();
    alternative1[0]['market'] = 'GOAL';
    alternative2[1]['market'] = 'UNDER 2.5';
    final body = readyBody();
    body['coupon'] = {
      'events': main,
      'coupons': [
        {'name': 'PRINCIPALE', 'events': main},
        {'name': 'ALTERNATIVA_1', 'events': alternative1},
        {'name': 'ALTERNATIVA_2', 'events': alternative2},
      ],
    };
    final service = GoalVdLineAutoCouponToday(
      client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
    );
    final result = await service.fetch(token: token);
    expect(result.isReady, true);
    expect(result.coupons.length, 3);
    expect(result.coupons[1].events[0].fixtureId, result.events[0].fixtureId);
  });

  test('reads only authenticated saved daily coupon', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(
        req.url.toString(),
        'https://goalvdline-learning-api.onrender.com/learning/v1/mobile/auto-coupon/today',
      );
      expect(req.headers['authorization'], 'Bearer $token');
      expect(req.body, isEmpty);
      return http.Response(jsonEncode(readyBody()), 200);
    });
    final service = GoalVdLineAutoCouponToday(client: client);
    final result = await service.fetch(token: token);
    expect(result.isReady, isTrue);
    expect(result.events.length, 3);
    expect(result.events.first.probability, 70.0);
    service.dispose();
  });

  test('invalid token prevents network request', () async {
    final service = GoalVdLineAutoCouponToday(
      client: MockClient((_) async => fail('No request expected')),
    );
    final result = await service.fetch(token: '');
    expect(result.isReady, isFalse);
    expect(result.message, contains('Token'));
  });

  test('not ready never renders any events', () async {
    final service = GoalVdLineAutoCouponToday(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'dayKey': '2026-11-09',
            'status': 'retry',
            'coupon': readyBody()['coupon'],
          }),
          200,
        ),
      ),
    );
    final result = await service.fetch(token: token);
    expect(result.isReady, isFalse);
    expect(result.events, isEmpty);
  });

  test('feature disabled and expired mobile token', () async {
    for (final status in [401, 503]) {
      final service = GoalVdLineAutoCouponToday(
        client: MockClient((_) async => http.Response('{}', status)),
      );
      expect((await service.fetch(token: token)).isReady, isFalse);
    }
  });

  test('rejects duplicate fixture ids in saved coupon', () async {
    final events = (readyBody()['coupon'] as Map)['events'] as List;
    final duplicate = [events[0], events[0], events[2]];
    final service = GoalVdLineAutoCouponToday(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(readyBody(duplicate.cast<Map<String, Object?>>())),
          200,
        ),
      ),
    );
    expect((await service.fetch(token: token)).isReady, isFalse);
  });

  test('rejects fabricated ready status without a valid coupon', () async {
    final service = GoalVdLineAutoCouponToday(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'dayKey': '2026-11-09',
            'status': 'ready',
            'coupon': {'events': []},
          }),
          200,
        ),
      ),
    );
    expect((await service.fetch(token: token)).isReady, isFalse);
  });
}
