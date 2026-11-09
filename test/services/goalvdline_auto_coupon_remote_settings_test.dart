import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_remote_settings.dart';

void main() {
  const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const prefs = GoalVdLineAutoCouponPreferences(requested: true);

  test('manual sync sends only preferences with a mobile token', () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(
        req.url.toString(),
        'https://goalvdline-learning-api.onrender.com/learning/v1/mobile/auto-coupon/preferences',
      );
      expect(req.headers['authorization'], 'Bearer $token');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body.keys.toList(), ['preferences']);
      expect((body['preferences'] as Map)['hour'], 8);
      return http.Response(
        jsonEncode({
          'success': true,
          'saved': true,
          'generationActive': false,
          'pushActive': false,
        }),
        200,
      );
    });
    final remote = GoalVdLineAutoCouponRemoteSettings(client: client);
    final message = await remote.send(preferences: prefs, token: token);
    expect(message, contains('sincronizzate'));
    remote.dispose();
  });

  test('does not send with missing or invalid token', () async {
    final client = MockClient((_) async => fail('No network calls expected'));
    final remote = GoalVdLineAutoCouponRemoteSettings(client: client);
    expect(await remote.send(preferences: prefs, token: ''), contains('Token'));
  });

  test(
    'cannot claim auto generation when server has not confirmed a safe state',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'saved': true,
            'generationActive': true,
            'pushActive': false,
          }),
          200,
        ),
      );
      final remote = GoalVdLineAutoCouponRemoteSettings(client: client);
      expect(
        await remote.send(preferences: prefs, token: token),
        contains('non verificabile'),
      );
    },
  );

  test('feature unavailable keeps local preferences safe', () async {
    final client = MockClient((_) async => http.Response('{}', 503));
    final remote = GoalVdLineAutoCouponRemoteSettings(client: client);
    expect(
      await remote.send(preferences: prefs, token: token),
      contains('non ancora abilitata'),
    );
  });
}
