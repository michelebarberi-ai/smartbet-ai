import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/goalvdline_quote_policy.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';
import 'package:smartbet_ai_new/services/smartbet_sports_market_selector.dart';

Map<String, Object> fixture(String bookmaker, int id, String homeOdd) => {
  'bookmakers': [
    {
      'id': id, 'name': bookmaker,
      'bets': [
        {'id': 1, 'name': 'Match Winner', 'values': [
          {'value': 'Home', 'odd': homeOdd},
          {'value': 'Draw', 'odd': '3.10'},
          {'value': 'Away', 'odd': '4.00'},
        ]},
      ],
    },
  ],
};

void main() {
  setUp(OddsService.clearCache);

  test('B47: when Sisal is missing, read actual quote from another bookmaker',
      () async {
    final service = OddsService(client: MockClient((_) async =>
        http.Response(jsonEncode({
          'errors': <String, Object>{},
          'response': [fixture('Bet365', 5, '1.26')],
        }), 200)));
    final odds = await service.getFixtureMarketOdds(fixtureId: 920001);
    expect(odds?.oddFor('1')?.odd, 1.26);
    expect(odds?.oddFor('1')?.bookmakerName, 'Bet365');
    expect(GoalVdLineQuotePolicy.isPlayable(odds?.oddFor('1')?.odd), true);
    service.dispose();
  });

  test('B47: no bookmaker quote never becomes an invented playable pick',
      () async {
    final service = OddsService(client: MockClient((_) async =>
        http.Response(jsonEncode({
          'errors': <String, Object>{},
          'response': <Object>[],
        }), 200)));
    final odds = await service.getFixtureMarketOdds(fixtureId: 920002);
    final recommendation = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: const {'UNDER 4.5': 94, 'OVER 1.5': 82},
      quotedOdds: {
        if (odds?.oddFor('UNDER 4.5') != null)
          'UNDER 4.5': odds!.oddFor('UNDER 4.5')!.odd,
      },
      minimumProbability: 65,
    )!;
    expect(recommendation.primary.market, 'UNDER 4.5');
    expect(recommendation.couponPick, isNull);
    service.dispose();
  });

  test('B47: 1.20 quote cannot displace more likely sporting outcome',
      () {
    final rec = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: const {
        'UNDER 4.5': 94, 'OVER 1.5': 82, 'GOAL': 70,
      },
      quotedOdds: const {
        'UNDER 4.5': 1.10, 'OVER 1.5': 1.20, 'GOAL': 1.24,
      },
      minimumProbability: 65,
    )!;
    expect(rec.primary.market, 'UNDER 4.5');
    expect(rec.primaryOdd, 1.10);
    expect(rec.couponPick?.market, 'GOAL');
    expect(rec.couponPick?.odd, 1.24);
  });
}
