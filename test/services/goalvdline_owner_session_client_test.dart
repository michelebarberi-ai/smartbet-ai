import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/screens/goalvdline_owner_access_screen.dart';
import 'package:smartbet_ai_new/services/goalvdline_owner_session_client.dart';

const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 43 chars.

class _Vault extends GoalVdLineOwnerSessionVault {
  String? current;
  @override Future<String?> read() async => current;
  @override Future<void> save(String value) async {
    if (!GoalVdLineOwnerSessionVault.validToken(value)) {
      throw const FormatException('Invalid token');
    }
    current = value;
  }
  @override Future<void> delete() async { current = null; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B59: owner access rejects malformed OTP before any network call', () async {
    var calls = 0;
    final vault = _Vault();
    final client = GoalVdLineOwnerSessionClient(
      vault: vault,
      client: MockClient((request) async {
        calls++;
        return http.Response('never reached', 500);
      }),
    );
    final result = await client.login(
      password: 'a very long sample passphrase',
      code: '34',
    );
    expect(result.success, isFalse);
    expect(calls, 0);
    expect(vault.current, isNull);
    client.dispose();
  });

  test('B59: incomplete server provisioning fails closed without saving secret', () async {
    final vault = _Vault();
    final client = GoalVdLineOwnerSessionClient(
      vault: vault,
      client: MockClient((request) async {
        expect(request.url.scheme, 'https');
        expect(request.url.path, '/owner/v1/login');
        expect(request.followRedirects, isFalse);
        return http.Response(jsonEncode({
          'success': false, 'error': 'Accesso non configurato',
        }), 503);
      }),
    );
    final result = await client.login(
      password: 'a very long sample passphrase',
      code: '123456',
    );
    expect(result.success, isFalse);
    expect(result.message, contains('non ancora configurato'));
    expect(vault.current, isNull);
    client.dispose();
  });

  test('B59: successful login never conflates owner session with admin token', () async {
    final vault = _Vault();
    var authorizedRequests = 0;
    final client = GoalVdLineOwnerSessionClient(
      vault: vault,
      client: MockClient((request) async {
        expect(request.followRedirects, false);
        if (request.url.path == '/owner/v1/login') {
          expect(request.headers.containsKey('x-smartbet-learning-admin'), false);
          expect(request.headers.containsKey('Authorization'), false);
          final submitted = jsonDecode(request.body) as Map;
          expect(submitted['password'], 'a very long sample passphrase');
          expect(submitted['code'], '123456');
          return http.Response(jsonEncode({
            'success': true,
            'scope': 'owner-staging-login-only',
            'token': token,
            'expiresInSeconds': 900,
          }), 200);
        }
        if (request.url.path == '/owner/v1/session') {
          authorizedRequests++;
          expect(request.headers['authorization'] ??
              request.headers['Authorization'], 'Bearer $token');
          return http.Response('{"success":true,"active":true}', 200);
        }
        if (request.url.path == '/owner/v1/logout') {
          return http.Response('{"success":true}', 200);
        }
        return http.Response('not found', 404);
      }),
    );
    final result = await client.login(
      password: 'a very long sample passphrase',
      code: '123456',
    );
    expect(result.success, true);
    expect(vault.current, token);
    expect(await client.hasValidSession(), true);
    expect(authorizedRequests, 1);
    await client.logout();
    expect(vault.current, isNull);
    client.dispose();
  });

  test('B59: no privilege from unapproved scope or malformed server response', () async {
    final vault = _Vault();
    final client = GoalVdLineOwnerSessionClient(
      vault: vault,
      client: MockClient((_) async => http.Response(jsonEncode({
        'success': true, 'scope': 'admin',
        'token': token, 'expiresInSeconds': 86400,
      }), 200)),
    );
    final result = await client.login(
      password: 'a very long sample passphrase',
      code: '123456',
    );
    expect(result.success, false);
    expect(vault.current, isNull);
    client.dispose();
  });

  test('B59: expired session is removed after server rejection', () async {
    final vault = _Vault()..current = token;
    final client = GoalVdLineOwnerSessionClient(
      vault: vault,
      client: MockClient((_) async => http.Response('{"success":false}', 401)),
    );
    expect(await client.hasValidSession(), false);
    expect(vault.current, isNull);
    client.dispose();
  });

  testWidgets('B59: login is displayed while server authentication is disabled', (tester) async {
    final client = GoalVdLineOwnerSessionClient(
      vault: _Vault(),
      client: MockClient((request) async {
        if (request.url.path == '/owner/v1/login') {
          return http.Response('{"success":false}', 503);
        }
        return http.Response('{"success":false}', 401);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: GoalVdLineOwnerAccessScreen(client: client),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b59-owner-login')), findsOneWidget);
    expect(find.byKey(const Key('b59-owner-dashboard')), findsNothing);
    await tester.enterText(find.byKey(const Key('b59-owner-password')),
        'a very long sample passphrase');
    await tester.enterText(find.byKey(const Key('b59-owner-totp')), '123456');
    await tester.ensureVisible(find.byKey(const Key('b59-owner-submit')));
    await tester.tap(find.byKey(const Key('b59-owner-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('non ancora configurato'), findsOneWidget);
    expect(find.byKey(const Key('b59-owner-dashboard')), findsNothing);
  });
}
