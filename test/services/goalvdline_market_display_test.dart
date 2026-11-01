import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_market_relation_service.dart';

void main() {
  test('P19B2D: handicap europeo esito 2 leggibile', () {
    expect(
      GoalVdLineMarketRelationService.displayMarket('HCP EURO CASA -2 2'),
      'HANDICAP EUROPEO · CASA -2 · ESITO 2',
    );
  });

  test('P19B2D: handicap esito X con segno positivo', () {
    expect(
      GoalVdLineMarketRelationService.displayMarket('hcp euro casa +1 x'),
      'HANDICAP EUROPEO · CASA +1 · ESITO X',
    );
  });

  test('P19B2D: mercati ordinari invariati', () {
    expect(
      GoalVdLineMarketRelationService.displayMarket('OVER 1.5'),
      'OVER 1.5',
    );
  });
}
