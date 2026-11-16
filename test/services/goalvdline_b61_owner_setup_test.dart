import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/screens/goalvdline_owner_setup_screen.dart';
import 'package:smartbet_ai_new/services/goalvdline_owner_setup_client.dart';

const ticket = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const manualKey = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B61: first activation is disabled when mail/database are not prepared', () async {
    final client = GoalVdLineOwnerSetupClient(
      client: MockClient((req) async {
        expect(req.url.scheme, 'https');
        expect(req.url.path, '/owner/v1/setup/status');
        return http.Response('{"ready":false}', 503);
      }),
    );
    final result = await client.status();
    expect(result.success, isFalse);
    expect(result.ready, isFalse);
    expect(result.message, contains('non ancora configurata'));
    client.dispose();
  });

  test('B62: a transient readiness GET failure retries once safely', () async {
    var statusRequests = 0;
    final client = GoalVdLineOwnerSetupClient(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/owner/v1/setup/status');
        statusRequests++;
        if (statusRequests == 1) throw StateError('Simulated cold start');
        return http.Response('{"ready":true,"activated":false}', 200);
      }),
    );
    final result = await client.status();
    expect(result.ready, isTrue);
    expect(result.success, isTrue);
    expect(statusRequests, 2);
    client.dispose();
  });

  test('B62: disabled owner backend does not trigger automatic retries', () async {
    var requests = 0;
    final client = GoalVdLineOwnerSetupClient(
      client: MockClient((request) async {
        requests++;
        return http.Response('{"ready":false}', 503);
      }),
    );
    final result = await client.status();
    expect(result.success, isFalse);
    expect(requests, 1);
    client.dispose();
  });

  test('B62: owner email request is never repeated on transport failure',
      () async {
    var postRequests = 0;
    final client = GoalVdLineOwnerSetupClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/owner/v1/setup/request');
        postRequests++;
        throw StateError('Simulated loss of response after email send');
      }),
    );
    final result = await client.requestCode();
    expect(result.success, isFalse);
    expect(result.message, contains('già stato inviato'));
    expect(postRequests, 1);
    client.dispose();
  });

  test('B61: full setup uses only server email, ephemeral ticket and TOTP code', () async {
    final paths = <String>[];
    final client = GoalVdLineOwnerSetupClient(
      client: MockClient((req) async {
        paths.add(req.url.path);
        expect(req.url.scheme, 'https');
        expect(req.followRedirects, isFalse);
        if (req.url.path == '/owner/v1/setup/status') {
          return http.Response('{"ready":true,"activated":false}', 200);
        }
        final data = jsonDecode(req.body) as Map<String, dynamic>;
        // The owner email is fixed on the backend, never accepted from UI.
        expect(data.containsKey('email'), isFalse);
        if (req.url.path == '/owner/v1/setup/request') {
          expect(data, isEmpty);
          return http.Response('{"success":true}', 202);
        }
        if (req.url.path == '/owner/v1/setup/verify') {
          expect(data['code'], '12345678');
          return http.Response(jsonEncode({
            'success':true, 'ticket':ticket, 'expiresInSeconds':600,
          }), 200);
        }
        final bearer = req.headers['authorization'] ?? req.headers['Authorization'];
        expect(bearer, 'Bearer $ticket');
        if (req.url.path == '/owner/v1/setup/totp/start') {
          expect(data, isEmpty);
          return http.Response(jsonEncode({
            'success':true, 'manualKey':manualKey,
          }), 200);
        }
        if (req.url.path == '/owner/v1/setup/finish') {
          expect(data['password'], 'An example secret with enough length');
          expect(data['code'], '123456');
          return http.Response('{"success":true,"activated":true}', 200);
        }
        return http.Response('missing', 404);
      }),
    );
    expect((await client.status()).ready, isTrue);
    expect((await client.requestCode()).success, isTrue);
    expect((await client.verifyEmail('12345678')).ticket, ticket);
    expect((await client.startAuthenticator(ticket)).totpManualKey, manualKey);
    expect((await client.finish(
      ticket:ticket,
      password:'An example secret with enough length',
      code:'123456',
    )).activated, isTrue);
    expect(paths, [
      '/owner/v1/setup/status',
      '/owner/v1/setup/request',
      '/owner/v1/setup/verify',
      '/owner/v1/setup/totp/start',
      '/owner/v1/setup/finish',
    ]);
    client.dispose();
  });

  testWidgets('B61: unavailable backend never exposes a password setup form',
      (tester) async {
    final client = GoalVdLineOwnerSetupClient(
      client: MockClient((_) async =>
          http.Response('{"ready":false}',503)),
    );
    await tester.pumpWidget(MaterialApp(
      home:GoalVdLineOwnerSetupScreen(client:client),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b61-setup-not-ready')), findsOneWidget);
    expect(find.byKey(const Key('b61-send-email-code')), findsNothing);
    expect(find.byKey(const Key('b61-new-password')), findsNothing);
  });

  testWidgets('B62: owner may recheck server without requesting an OTP',
      (tester) async {
    var statusChecks = 0;
    var emailRequests = 0;
    final client = GoalVdLineOwnerSetupClient(
      client: MockClient((request) async {
        if (request.url.path == '/owner/v1/setup/status') {
          statusChecks++;
          return statusChecks == 1
              ? http.Response('{"ready":false}', 503)
              : http.Response('{"ready":true,"activated":false}', 200);
        }
        emailRequests++;
        return http.Response('{}', 503);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: GoalVdLineOwnerSetupScreen(client: client),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b62-retry-owner-status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('b62-retry-owner-status')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b61-send-email-code')), findsOneWidget);
    expect(statusChecks, 2);
    expect(emailRequests, 0);
  });

  testWidgets('B61: screen progresses through email and TOTP before password',
      (tester) async {
    final client=GoalVdLineOwnerSetupClient(
      client:MockClient((req) async {
        switch(req.url.path) {
          case '/owner/v1/setup/status':
            return http.Response('{"ready":true,"activated":false}',200);
          case '/owner/v1/setup/request':
            return http.Response('{"success":true}',202);
          case '/owner/v1/setup/verify':
            return http.Response(jsonEncode({'success':true,'ticket':ticket}),200);
          case '/owner/v1/setup/totp/start':
            return http.Response(jsonEncode({
              'success':true,'manualKey':manualKey,
            }),200);
          case '/owner/v1/setup/finish':
            return http.Response('{"success":true,"activated":true}',200);
        }
        return http.Response('missing',404);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home:GoalVdLineOwnerSetupScreen(client:client),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b61-send-email-code')), findsOneWidget);
    await tester.tap(find.byKey(const Key('b61-send-email-code')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b61-email-code')), findsOneWidget);
    expect(find.byKey(const Key('b61-new-password')), findsNothing);
    await tester.enterText(find.byKey(const Key('b61-email-code')), '12345678');
    await tester.ensureVisible(find.byKey(const Key('b61-verify-email')));
    await tester.tap(find.byKey(const Key('b61-verify-email')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b61-authenticator-manual-key')), findsOneWidget);
    expect(find.byKey(const Key('b61-new-password')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('b61-new-password')),
      'A password chosen only by the owner');
    await tester.enterText(find.byKey(const Key('b61-confirm-password')),
      'A password chosen only by the owner');
    await tester.enterText(find.byKey(const Key('b61-first-totp')), '123456');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.byKey(const Key('b61-finish-activation')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('b61-finish-activation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b61-back-to-login')), findsOneWidget);
    expect(find.byKey(const Key('b61-authenticator-manual-key')), findsNothing);
  });
}
