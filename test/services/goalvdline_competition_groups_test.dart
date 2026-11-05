import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_competition_groups.dart';

class _Row {
  final int id;
  final String country;
  final String league;
  final String date;
  const _Row(this.id, this.country, this.league, this.date);
}

void main() {
  testWidgets('P22: raggruppa senza perdere o duplicare partite', (
    tester,
  ) async {
    final items = <_Row>[
      const _Row(1, 'Sweden', 'Allsvenskan', '2026-11-04T20:00:00Z'),
      const _Row(2, 'Italy', 'Serie A', '2026-11-04T18:00:00Z'),
      const _Row(3, 'Italy', 'Serie A', '2026-11-04T16:00:00Z'),
      const _Row(4, 'England', 'Premier League', '2026-11-04T19:00:00Z'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoalVdLineCompetitionGroups<_Row>(
              items: items,
              namespace: 'p22-widget-test',
              countryOf: (item) => item.country,
              leagueOf: (item) => item.league,
              dateOf: (item) => item.date,
              itemBuilder: (_, item) => Text('ID:${item.id}'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 1; i <= 4; i++) {
      expect(find.text('ID:$i'), findsOneWidget);
    }
    expect(find.text('🇮🇹 ITALIA'), findsOneWidget);
    expect(find.text('🏴 INGHILTERRA'), findsOneWidget);
    expect(find.text('SVEZIA'), findsNothing); // intestazione con bandiera
    expect(find.text('🇸🇪 SVEZIA'), findsOneWidget);
    expect(items.map((e) => e.id).toList(), [1, 2, 3, 4]);
    // L'ordinamento del gruppo Italia e' cronologico.
    final italian = tester.getTopLeft(find.text('ID:3'));
    final later = tester.getTopLeft(find.text('ID:2'));
    expect(italian.dy, lessThan(later.dy));
  });
}
