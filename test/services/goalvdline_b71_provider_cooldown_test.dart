import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_odds_scan_guard.dart';

void main() {
  setUp(OddsService.clearCache);

  test('B71: Render cooldown HTTP 503 respects Retry-After across fixtures',
      () async {
    var now = DateTime(2026, 11, 18, 20);
    var actualHttpCalls = 0;
    final client = MockClient((request) async {
      actualHttpCalls++;
      if (actualHttpCalls == 1) {
        return http.Response(jsonEncode({
          'success': false,
          'code': 'FOOTBALL_PROVIDER_COOLDOWN',
          'error': 'Dati sportivi temporaneamente sospesi per limite del fornitore.',
        }), 503, headers: {'retry-after': '120'});
      }
      return http.Response(jsonEncode({
        'errors': <String, dynamic>{},
        'response': <dynamic>[],
      }), 200);
    });
    final service = OddsService(client: client, now: () => now);

    await service.getFixtureMarketOdds(fixtureId: 987001);
    expect(service.diagnosticFor(fixtureId: 987001)?.status,
        OddsLookupStatus.quotaOrRateLimit);
    expect(service.diagnosticFor(fixtureId: 987001)?.httpStatus, 503);

    await service.getFixtureMarketOdds(fixtureId: 987002);
    expect(actualHttpCalls, 1);
    expect(service.diagnosticFor(fixtureId: 987002)?.status,
        OddsLookupStatus.providerCooldownActive);
    expect(service.diagnosticFor(fixtureId: 987002)?.httpStatus, isNull);
    final blocked = [
      const OddsLookupDiagnostic(status: OddsLookupStatus.providerCooldownActive),
      const OddsLookupDiagnostic(status: OddsLookupStatus.providerCooldownActive),
    ];
    expect(GoalVdLineOddsScanGuard.stopAfterBatch(
      diagnostics: blocked,
      consecutiveFailedBatches: 1,
    ), isTrue);

    now = now.add(const Duration(seconds: 121));
    await service.getFixtureMarketOdds(fixtureId: 987003);
    expect(actualHttpCalls, 2);
    expect(service.diagnosticFor(fixtureId: 987003)?.status,
        OddsLookupStatus.noFeedRows);
    service.dispose();
  });

  test('B71: structured provider rate limit HTTP 502 begins bounded pause',
      () async {
    var calls = 0;
    final service = OddsService(client: MockClient((_) async {
      calls++;
      return http.Response(jsonEncode({
        'success': false,
        'code': 'FOOTBALL_PROVIDER_RATE_LIMIT',
        'error': 'Limite temporaneo del fornitore sportivo.',
      }), 502);
    }));
    await service.getFixtureMarketOdds(fixtureId: 987004);
    expect(service.diagnosticFor(fixtureId: 987004)?.status,
        OddsLookupStatus.quotaOrRateLimit);
    await service.getFixtureMarketOdds(fixtureId: 987005);
    expect(calls, 1);
    expect(service.diagnosticFor(fixtureId: 987005)?.status,
        OddsLookupStatus.providerCooldownActive);
    service.dispose();
  });

  test('B71: ordinary 503 is NOT misclassified as provider quota',
      () async {
    var calls = 0;
    final service = OddsService(client: MockClient((_) async {
      calls++;
      return http.Response('Service Unavailable', 503);
    }));
    await service.getFixtureMarketOdds(fixtureId: 987006);
    await service.getFixtureMarketOdds(fixtureId: 987007);
    expect(calls, 2);
    expect(service.diagnosticFor(fixtureId: 987006)?.status,
        OddsLookupStatus.upstreamUnavailable);
    service.dispose();
  });

  test('B71: server key error with sanitized machine code is config, not quota',
      () async {
    final service = OddsService(client: MockClient((_) async =>
      http.Response(jsonEncode({
        'success': false,
        'code': 'FOOTBALL_PROVIDER_KEY_MISSING',
        'error': 'Dati sportivi non configurati sul server.',
      }), 503),
    ));
    await service.getFixtureMarketOdds(fixtureId: 987008);
    expect(service.diagnosticFor(fixtureId: 987008)?.status,
        OddsLookupStatus.proxyConfigurationError);
    service.dispose();
  });

  test('B71: no synthetic price or success from an API cooldown', () async {
    final service = OddsService(client: MockClient((_) async =>
      http.Response(jsonEncode({
        'success': false,
        'code': 'FOOTBALL_PROVIDER_COOLDOWN',
      }), 503, headers: {'retry-after': '1800'}),
    ));
    final odds = await service.getFixtureMarketOdds(fixtureId: 987009);
    expect(odds, isNull);
    expect(service.diagnosticFor(fixtureId: 987009)?.status,
        OddsLookupStatus.quotaOrRateLimit);
    service.dispose();
  });
}
