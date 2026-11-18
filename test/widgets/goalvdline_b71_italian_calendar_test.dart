import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartbet_ai_new/services/goalvdline_quote_policy.dart';

void main() {
  test('B71: Palinsesto Italia is on by default and still optional', () {
    expect(GoalVdLineQuotePolicy.italianOnlyByDefault, isTrue);
    expect(GoalVdLineQuotePolicy.minimumOdd, 1.20);
  });

  testWidgets('B71: Italian Material date localizations display month and day',
      (tester) async {
    const locale = Locale('it', 'IT');
    final strings = await GlobalMaterialLocalizations.delegate.load(locale);
    expect(strings.formatMonthYear(DateTime(2026, 11, 20)).toLowerCase(),
        contains('novembre'));
    expect(strings.formatMediumDate(DateTime(2026, 11, 20)).toLowerCase(),
        contains('nov'));

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: Text('Calendario')),
    ));
    expect(MaterialLocalizations.of(tester.element(find.text('Calendario')))
        .localeName, 'it_IT');
  });
}
