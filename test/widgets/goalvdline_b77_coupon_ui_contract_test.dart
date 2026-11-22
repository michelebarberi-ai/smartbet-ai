import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/widgets/add_to_personal_coupon_button.dart';

void main() {
  test('B77: retired Server Beta is not mounted in Create Schedina', () {
    final source = File('lib/screens/create_ai_coupon_screen.dart')
        .readAsStringSync();
    expect(source, isNot(contains('GoalVdLineOnDemandCouponPanel(')));
    expect(source, isNot(contains("import '../widgets/goalvdline_on_demand_coupon_panel.dart';")));
  });

  testWidgets('B77: saving a pick is a clearly styled secondary action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AddToPersonalCouponButton(
          fixtureId: '1',
          match: 'Casa - Ospite',
          market: 'UNDER 4.5',
          source: 'Crea Schedina',
        ),
      ),
    ));

    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.text('Salva nella mia schedina'), findsOneWidget);
  });

  test('B77: save action is in each result card footer', () {
    final create = File('lib/screens/create_ai_coupon_screen.dart')
        .readAsStringSync();
    final combinations = File('lib/screens/combinations_ai_screen.dart')
        .readAsStringSync();

    final createCard = create.substring(create.indexOf('Widget _resultCard('));
    final combinationsCard =
        combinations.substring(combinations.indexOf('Widget _resultCard('));
    expect(
      createCard.indexOf("Text(\n            'Controllo locale:"),
      lessThan(createCard.indexOf("source: 'Crea Schedina'")),
    );
    expect(
      combinationsCard.indexOf("'Rischio pre-analisi:"),
      lessThan(combinationsCard.indexOf("source: 'Combinazioni AI'")),
    );
  });
}
