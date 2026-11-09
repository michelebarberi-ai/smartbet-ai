import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_push_registration.dart';

void main() {
  const mobileToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const apnsToken =
      'abababababababababababababababababababababababababababababababab';

  test(
    'does not request iOS permission if registration is disabled remotely',
    () async {
      var asked = false;
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/learning/v1/status');
        return http.Response(
          jsonEncode({'autoCouponDeviceRegistrationEnabled': false}),
          200,
        );
      });
      final service = GoalVdLineAutoCouponPushRegistration(
        client: client,
        requestDeviceToken: () async {
          asked = true;
          return apnsToken;
        },
      );
      expect(
        await service.register(token: mobileToken),
        contains('non ancora abilitata'),
      );
      expect(asked, isFalse);
      service.dispose();
    },
  );

  test(
    'explicit opt-in sends APNs token only to authenticated mobile endpoint',
    () async {
      var asked = false;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'autoCouponDeviceRegistrationEnabled': true}),
            200,
          );
        }
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://goalvdline-learning-api.onrender.com/learning/v1/mobile/auto-coupon/push/register',
        );
        expect(request.headers['authorization'], 'Bearer $mobileToken');
        final body = jsonDecode(request.body) as Map;
        expect(body.keys.toList(), ['deviceToken']);
        expect(body['deviceToken'], apnsToken);
        return http.Response(
          jsonEncode({
            'success': true,
            'registered': true,
            'pushActive': false,
          }),
          200,
        );
      });
      final service = GoalVdLineAutoCouponPushRegistration(
        client: client,
        requestDeviceToken: () async {
          asked = true;
          return apnsToken;
        },
      );
      expect(
        await service.register(token: mobileToken),
        contains('iPhone registrato'),
      );
      expect(asked, isTrue);
      service.dispose();
    },
  );

  test(
    'invalid mobile token never requests APNs permission or network',
    () async {
      final client = MockClient((_) async => fail('No network expected'));
      final service = GoalVdLineAutoCouponPushRegistration(
        client: client,
        requestDeviceToken: () async {
          fail('No permission expected');
        },
      );
      expect(
        await service.register(token: ''),
        contains('Token mobile mancante'),
      );
      service.dispose();
    },
  );

  test('APNs permission denial never registers with the backend', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'GET');
      return http.Response(
        jsonEncode({'autoCouponDeviceRegistrationEnabled': true}),
        200,
      );
    });
    final service = GoalVdLineAutoCouponPushRegistration(
      client: client,
      requestDeviceToken: () async => null,
    );
    expect(
      await service.register(token: mobileToken),
      contains('Permesso notifiche negato'),
    );
    expect(calls, 1);
    service.dispose();
  });

  test(
    'revoking registration uses mobile credentials without APNs token',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/learning/v1/mobile/auto-coupon/push/unregister',
        );
        expect(request.headers['authorization'], 'Bearer $mobileToken');
        expect(jsonDecode(request.body), isEmpty);
        return http.Response(
          jsonEncode({
            'success': true,
            'registered': false,
            'pushActive': false,
          }),
          200,
        );
      });
      final service = GoalVdLineAutoCouponPushRegistration(client: client);
      expect(await service.unregister(token: mobileToken), contains('rimossa'));
      service.dispose();
    },
  );
}
