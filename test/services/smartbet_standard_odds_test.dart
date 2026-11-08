import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbet_ai_new/services/odds_service.dart';

void main() {
  test('usa solo quote finite per la linea e il periodo richiesti', () async {
    final service = OddsService(client: MockClient((_) async {
      return http.Response(jsonEncode({
        'errors': {},
        'response': [
          {
            'bookmakers': [
              {
                'id': 77,
                'name': 'Prova',
                'bets': [
                  {
                    'name': 'Goals Over/Under',
                    'values': [
                      {'value': 'Over 2,5', 'odd': '1,82'},
                      {'value': 'Over 2.5', 'odd': 'Infinity'},
                      {'value': 'Over 2.5 / Under 3.5', 'odd': '8.0'},
                    ],
                  },
                  {
                    'id': 6,
                    'name': 'Goals Over/Under',
                    'values': [
                      {'value': 'Over 2.5', 'odd': '9.0'},
                    ],
                  },
                  {
                    'id': 49,
                    'values': [
                      {'value': 'o/yes 2.5', 'odd': '2.1'},
                      {'value': 'o/yes 12.5', 'odd': '15.0'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      }), 200);
    }));
    addTearDown(service.dispose);
    final odds = await service.getFixtureMarketOdds(fixtureId: 765432109);
    expect(odds?.oddFor('OVER 2.5')?.odd, 1.82);
    expect(odds?.oddFor('GOAL + O2.5')?.odd, 2.1);
    expect(odds?.oddFor('UNDER 3.5'), isNull);
  });
}
