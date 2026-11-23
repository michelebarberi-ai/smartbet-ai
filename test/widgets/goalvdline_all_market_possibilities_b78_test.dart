import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_market_opportunity_service.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_market_opportunity_panel.dart';

void main() {
  testWidgets('B78: all modeled possibilities survive the coupon shortlist',
      (tester) async {
    final report = const GoalVdLineMarketOpportunityService().compare(
      sportingPercent: {
        '1X': 85,
        'MULTIGOL 1-4': 82,
        'UNDER 4.5': 79,
        'GOAL O OVER 2.5': 76,
        'CASA SEGNA': 75,
        'GOAL + O2.5': 61,
      },
      country: 'Italia',
      league: 'Serie A',
      selectedMarket: 'MULTIGOL 1-4',
      quotedOdds: {'MULTIGOL 1-4': 1.35},
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoalVdLineMarketOpportunityPanel(report: report),
        ),
      ),
    ));

    await tester.tap(find.text('Mercati analizzati · controllo quote'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mostra tutte le 6 possibilità'), findsOneWidget);
    expect(find.textContaining('GOAL O OVER 2.5'), findsNothing);

    await tester.tap(find.textContaining('Mostra tutte le 6 possibilità'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GOAL O OVER 2.5'), findsOneWidget);
    expect(find.textContaining('CASA SEGNA'), findsOneWidget);
    expect(find.textContaining('GOAL + O2.5'), findsOneWidget);
  });
}
