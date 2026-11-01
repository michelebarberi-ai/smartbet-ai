import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_market_relation_service.dart';

void main() {
  GoalVdLineMarketRelation compare(String a, String b) =>
      GoalVdLineMarketRelationService.compare(
        goalVdLineMarket: a,
        diegoMarket: b,
      );

  test('P19B2C: 12 e Over 1.5 compatibili', () {
    final result = compare('12', 'OVER 1.5');
    expect(result.kind, GoalVdLineMarketRelationKind.compatible);
    expect(result.title, 'COMPATIBILI');
  });

  test('P19B2C: Goal e No Goal incompatibili', () {
    expect(
      compare('GOAL', 'NO GOAL').kind,
      GoalVdLineMarketRelationKind.incompatible,
    );
  });

  test('P19B2C: 1 e X incompatibili', () {
    expect(compare('1', 'X').kind, GoalVdLineMarketRelationKind.incompatible);
  });

  test('P19B2C: Over e Under 1.5 incompatibili', () {
    expect(
      compare('OVER 1.5', 'UNDER 1.5').kind,
      GoalVdLineMarketRelationKind.incompatible,
    );
  });

  test('P19B2C: vittoria casa implica casa segna', () {
    final result = compare('1', 'CASA SEGNA');
    expect(result.kind, GoalVdLineMarketRelationKind.compatible);
    expect(result.title, 'GOALVDLINE IMPLICA DIEGO');
  });

  test('P19B2C: Goal e BTTS YES equivalenti', () {
    expect(compare('GOAL', 'BTTS YES').kind, GoalVdLineMarketRelationKind.same);
  });

  test('P19B2C: 1X e X2 compatibili', () {
    expect(compare('1X', 'X2').kind, GoalVdLineMarketRelationKind.compatible);
  });

  test('P19B2C: handicap europeo confrontabile', () {
    expect(
      compare('HCP EURO CASA -3 2', 'UNDER 4.5').kind,
      GoalVdLineMarketRelationKind.compatible,
    );
  });

  test('P19B2C: combo contraddittorie', () {
    expect(
      compare('GOAL + O2.5', 'NO GOAL + U2.5').kind,
      GoalVdLineMarketRelationKind.incompatible,
    );
  });

  test('P19B2C: mercato temporale non supportato', () {
    expect(
      compare('CASA SEGNA PRIMA', 'OVER 1.5').kind,
      GoalVdLineMarketRelationKind.unavailable,
    );
  });

  test('P19B2C: previsione assente', () {
    expect(
      compare('N/D', 'OVER 1.5').kind,
      GoalVdLineMarketRelationKind.unavailable,
    );
  });
}
