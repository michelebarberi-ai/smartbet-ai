import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';

Map<String, dynamic> response(List<dynamic> entries) =>
    {'errors': <String, dynamic>{}, 'response': entries};

Map<String, dynamic> bookmaker({
  String name = 'Bet365',
  int betId = 1,
  String value = 'Home',
  String odd = '1.95',
}) => {
  'bookmakers': [{
    'id': 5, 'name': name,
    'bets': [{
      'id': betId,
      'name': betId == 1 ? 'Match Winner' : 'Unrecognized Market',
      'values': [{'value': value, 'odd': odd}],
    }],
  }],
};

Future<OddsLookupDiagnostic?> check({
  required http.Response Function() reply,
  int fixture = 980001,
  bool italianOnly = false,
}) async {
  final service = OddsService(client: MockClient((_) async => reply()));
  addTearDown(service.dispose);
  await service.getFixtureMarketOdds(
    fixtureId: fixture,
    italianBookmakerOnly: italianOnly,
  );
  return service.diagnosticFor(
    fixtureId: fixture,
    italianBookmakerOnly: italianOnly,
  );
}

void main() {
  setUp(OddsService.clearCache);

  test('B68: true empty response is distinguished from an API failure',
      () async {
    final result = await check(reply: () =>
        http.Response(jsonEncode(response([])), 200));
    expect(result?.status, OddsLookupStatus.noFeedRows);
    expect(result?.recognizedMarketCount, 0);
  });

  test('B68: provider returns HTTP 502, never shown as uncovered fixture',
      () async {
    final result = await check(reply: () => http.Response(
      '{"success":false,"error":"Errore temporaneo quote"}', 502,
    ));
    expect(result?.status, OddsLookupStatus.upstreamUnavailable);
    expect(result?.httpStatus, 502);
  });

  test('B68: rate limit and quota messages are categorized distinctly',
      () async {
    final result = await check(reply: () => http.Response(
      '{"error":"You have reached your daily limit of requests."}', 502,
    ));
    expect(result?.status, OddsLookupStatus.quotaOrRateLimit);
    final second = await check(fixture: 980002, reply: () =>
        http.Response('Too many requests', 429));
    expect(second?.status, OddsLookupStatus.quotaOrRateLimit);
  });

  test('B68: API-SPORTS HTTP 200 error field is not no-feed-data',
      () async {
    final result = await check(reply: () => http.Response(jsonEncode({
      'errors': {'requests': 'Your quota is exhausted'},
      'response': <dynamic>[],
    }), 200));
    expect(result?.status, OddsLookupStatus.quotaOrRateLimit);
    final general = await check(fixture: 980003,
      reply: () => http.Response(jsonEncode({
        'errors': {'season': 'invalid'},
        'response': <dynamic>[],
      }), 200));
    expect(general?.status, OddsLookupStatus.providerError);
  });

  test('B68: missing country-eligible bookmakers is not missing raw feed',
      () async {
    final result = await check(
      fixture: 980004,
      italianOnly: true,
      reply: () => http.Response(jsonEncode(response([
        bookmaker(name: 'Pinnacle'),
      ])), 200),
    );
    expect(result?.status, OddsLookupStatus.noItalianBookmakers);
  });

  test('B68: offered unsupported market is not invented as quoted goal',
      () async {
    final result = await check(fixture: 980005,
      reply: () => http.Response(jsonEncode(response([
        bookmaker(betId: 3333, value: 'First half custom market'),
      ])), 200));
    expect(result?.status, OddsLookupStatus.unsupportedMarkets);
    expect(result?.bookmakerCount, 1);
    expect(result?.recognizedMarketCount, 0);
  });

  test('B68: recognized real quote and market count are reported',
      () async {
    final result = await check(fixture: 980006,
      reply: () => http.Response(jsonEncode(response([
        bookmaker(odd: '1.67'),
      ])), 200));
    expect(result?.status, OddsLookupStatus.available);
    expect(result?.bookmakerCount, 1);
    expect(result?.recognizedMarketCount, 1);
  });

  test('B68: cached response retains diagnostics for a new service instance',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(jsonEncode(response([
        bookmaker(name: 'Sisal', odd: '1.80'),
      ])), 200);
    });
    final first = OddsService(client: client);
    await first.getFixtureMarketOdds(fixtureId: 980007);
    final second = OddsService(client: MockClient((_) async {
      throw StateError('Cached data should not send a new request');
    }));
    final odds = await second.getFixtureMarketOdds(fixtureId: 980007);
    expect(calls, 1);
    expect(odds?.oddFor('1')?.odd, 1.80);
    expect(second.diagnosticFor(fixtureId: 980007)?.status,
      OddsLookupStatus.available);
    first.dispose();
    second.dispose();
  });

  test('B68: no raw bookmakers is distinct from parsing failure',
      () async {
    final result = await check(fixture: 980008,
      reply: () => http.Response(jsonEncode(response([
        {'bookmakers': <dynamic>[]},
      ])), 200));
    expect(result?.status, OddsLookupStatus.noBookmakers);
  });

  test('B68: malformed payload is explicitly untrusted', () async {
    final result = await check(fixture: 980009,
      reply: () => http.Response(jsonEncode({'response': 'not a list'}), 200));
    expect(result?.status, OddsLookupStatus.invalidPayload);
  });
}
