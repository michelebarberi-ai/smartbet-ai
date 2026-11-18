import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/goalvdline_palinsesto_digest_registration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final token = List.filled(43, 'A').join();
  final device = List.filled(64, 'b').join();
  const origin = 'https://learning.example.org';

  test('B73: subscribe only after explicit opt-in and enabled server gate', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path == '/learning/v1/status') {
        return http.Response(jsonEncode({
          'dailyPalinsestoRegistrationEnabled': true,
        }), 200);
      }
      expect(request.url.path, '/learning/v1/mobile/palinsesto/subscribe');
      expect(request.headers['Authorization'], 'Bearer $token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['deviceToken'], device);
      expect(body['hour'], 8);
      expect(body['minute'], 0);
      expect(body.containsKey('events'), isFalse);
      return http.Response(jsonEncode({
        'success': true, 'registered': true, 'pushActive': true,
      }), 200);
    });
    final service = GoalVdLinePalinsestoDigestRegistration(
      client: client,
      readMobileToken: () async => token,
      requestDeviceToken: () async => device,
    );
    final result = await service.subscribe(hour: 8, minute: 0,
        serverUrl: origin);
    expect(result.success, isTrue);
    expect(result.pushActive, isTrue);
    expect(calls.length, 2);
    service.dispose();
  });

  test('B73: disabled server never requests iPhone APNs token', () async {
    var deviceRead = false;
    final client = MockClient((_) async => http.Response(jsonEncode({
      'dailyPalinsestoRegistrationEnabled': false,
    }), 200));
    final service = GoalVdLinePalinsestoDigestRegistration(
      client: client,
      readMobileToken: () async => token,
      requestDeviceToken: () async {
        deviceRead = true;
        return device;
      },
    );
    final result = await service.subscribe(hour: 8, minute: 0,
        serverUrl: origin);
    expect(result.success, isFalse);
    expect(result.pushActive, isFalse);
    expect(deviceRead, isFalse);
  });

  test('B73: unsubscribe uses only authenticated protected removal route', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/learning/v1/mobile/palinsesto/unsubscribe');
      expect(request.headers['Authorization'], 'Bearer $token');
      expect(request.body, '{}');
      return http.Response(jsonEncode({
        'success': true, 'registered': false, 'pushActive': false,
      }), 200);
    });
    final service = GoalVdLinePalinsestoDigestRegistration(
      client: client, readMobileToken: () async => token);
    final result = await service.unsubscribe(serverUrl: origin);
    expect(result.success, isTrue);
    expect(result.pushActive, isFalse);
  });

  test('B73: absent bearer token and invalid time cannot subscribe', () async {
    var remoteCalls=0;
    final service=GoalVdLinePalinsestoDigestRegistration(
      client:MockClient((_) async {remoteCalls++;return http.Response('{}',500);}),
      readMobileToken:() async=>null,
      requestDeviceToken:() async=>device,
    );
    expect((await service.subscribe(hour: 8,minute: 0,
        serverUrl:origin)).success,isFalse);
    expect((await service.subscribe(hour: 99,minute: 0,
        serverUrl:origin)).success,isFalse);
    expect(remoteCalls,0);
  });
}
