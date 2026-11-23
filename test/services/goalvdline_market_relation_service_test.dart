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

  test('B64: X2 e ospite segna spiegati con lettura sportiva', () {
    final reading = compare('X2', 'OSPITE SEGNA');
    expect(reading.kind, GoalVdLineMarketRelationKind.compatible);
    expect(reading.explanation, contains('favorevole agli ospiti'));
    expect(reading.explanation, contains('potenziale offensivo'));
    expect(reading.explanation, isNot(contains('una può vincere')));
    expect(reading.explanation, isNot(contains('0-1')));
  });

  test('B64: interpretazione casa e fallback senza frasi meccaniche', () {
    final home = compare('1X', 'CASA SEGNA');
    expect(home.explanation, contains('squadra di casa'));
    final other = compare('12', 'OVER 1.5');
    expect(other.explanation, contains('SmartBet propone'));
    expect(other.explanation, contains('Diego indica'));
    expect(other.explanation, isNot(contains('l’altra perde')));
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
  test('B79: Asian +1.5 away is logically implied by X2', () {
    final result = compare('HCP ASIA OSPITE 1.5', 'X2');
    expect(result.kind, GoalVdLineMarketRelationKind.compatible);
    expect(result.title, 'DIEGO IMPLICA GOALVDLINE');
  });

  test('B79: Asian -1.5 away conflicts with home-or-draw', () {
    final result = compare('HCP ASIA OSPITE -1.5', '1X');
    expect(result.kind, GoalVdLineMarketRelationKind.incompatible);
  });

  test('B79: Asian positive sign is explicit in the UI, not odds key', () {
    expect(
      GoalVdLineMarketRelationService.displayMarket('HCP ASIA OSPITE 1.5'),
      'HCP ASIA OSPITE +1.5',
    );
    expect(
      GoalVdLineMarketRelationService.displayMarket('HCP ASIA OSPITE -1.5'),
      'HCP ASIA OSPITE -1.5',
    );
    expect(compare('HCP ASIA OSPITE -0.75', 'X2').kind,
        GoalVdLineMarketRelationKind.unavailable);
  });

}
