import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/screens/goalvdline_auto_coupon_today_screen.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_today.dart';

void main() {
  testWidgets('shows only verified server coupon data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GoalVdLineAutoCouponTodayScreen(
          load: () async => GoalVdLineTodayCouponResult(
            'Schedina pronta.',
            events: [
              GoalVdLineTodayCouponEvent(
                fixtureId: 123,
                market: '1X2',
                probability: 72,
                kickoffAt: DateTime.utc(2026, 11, 9, 19),
                odds: 1.82,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Schedina pronta.'), findsOneWidget);
    expect(find.textContaining('Partita #123'), findsOneWidget);
    expect(find.textContaining('72.0%'), findsOneWidget);
    expect(find.textContaining('Quota 1.82'), findsOneWidget);
  });

  testWidgets('does not invent events while coupon is missing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GoalVdLineAutoCouponTodayScreen(
          load: () async =>
              const GoalVdLineTodayCouponResult('Ancora non pronta.'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ancora non pronta.'), findsOneWidget);
    expect(find.textContaining('Partita #'), findsNothing);
  });
}
