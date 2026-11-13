import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/sisal_odds_service.dart';

Map<String, Object> fixtureBookmaker(String name, int id) => {
  'bookmakers': [
    {
      'id': id,
      'name': name,
      'bets': [
        {
          'id': 1,
          'name': 'Match Winner',
          'values': [
            {'value': 'Home', 'odd': '1.90'},
            {'value': 'Draw', 'odd': '3.20'},
            {'value': 'Away', 'odd': '4.20'},
          ],
        },
      ],
    },
  ],
};

void main() {
  setUp(OddsService.clearCache);

  test('B45: no Sisal in provider never becomes a fake Sisal coupon', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({
      'errors': <String, Object>{},
      'response': [fixtureBookmaker('Bet365', 5)],
    }), 200));
    final service = SisalOddsService(oddsService: OddsService(client: client));
    expect(await service.getFixtureMarketOdds(fixtureId: 98100001), isNull);
    service.dispose();
  });

  test('B45: Sisal-only lookup ignores higher odds from other providers',
      () async {
    final client = MockClient((_) async => http.Response(jsonEncode({
      'errors': <String, Object>{},
      'response': [
        fixtureBookmaker('Bet365', 5),
        fixtureBookmaker('Sisal', 42),
      ],
    }), 200));
    final service = SisalOddsService(oddsService: OddsService(client: client));
    final odds = await service.getFixtureMarketOdds(fixtureId: 98100002);
    expect(odds, isNotNull);
    expect(odds!.oddFor('1')?.bookmakerName, 'Sisal');
    expect(odds.oddFor('1')?.odd, 1.90);
    service.dispose();
  });

  test('B45: missing Sisal cache retries after expiry, not forever', () async {
    var now = DateTime.utc(2026, 11, 13, 9);
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(jsonEncode({
        'errors': <String, Object>{},
        'response': [
          fixtureBookmaker(calls == 1 ? 'Bet365' : 'Sisal', calls),
        ],
      }), 200);
    });
    final service = SisalOddsService(
      oddsService: OddsService(client: client, now: () => now),
    );

    expect(await service.getFixtureMarketOdds(fixtureId: 98100004), isNull);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 5));
    expect(await service.getFixtureMarketOdds(fixtureId: 98100004), isNull);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 6));
    final recovered =
        await service.getFixtureMarketOdds(fixtureId: 98100004);
    expect(recovered?.oddFor('1')?.bookmakerName, 'Sisal');
    expect(calls, 2);
    service.dispose();
  });

  test('B45: no bookmakers yields no available coupon quotes', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({
      'errors': <String, Object>{},
      'response': [
        {'bookmakers': <Object>[]},
      ],
    }), 200));
    final service = SisalOddsService(oddsService: OddsService(client: client));
    final odds = await service.getFixtureMarketOdds(fixtureId: 98100003);
    expect(odds == null || odds.bestByOutcome.isEmpty, true);
    service.dispose();
  });
}
