import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_daily_matches_card.dart';

void main() {
  Widget app({required int? count, bool loading = false, VoidCallback? onTap}) =>
      MaterialApp(
        home: Scaffold(
          body: GoalVdLineDailyMatchesCard(
            count: count,
            loading: loading,
            onCreateCoupon: onTap ?? () {},
          ),
        ),
      );

  testWidgets('B45: morning count is shown as candidates, not AI certainties',
      (tester) async {
    await tester.pumpWidget(app(count: 12));
    expect(find.byKey(const Key('b45-daily-count')), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining('12 partite future disponibili'), findsOneWidget);
    expect(find.textContaining('non significa'), findsOneWidget);
  });

  testWidgets('B45: missing feed is N/D, never falsely zero',
      (tester) async {
    await tester.pumpWidget(app(count: null));
    expect(find.text('N/D'), findsOneWidget);
    expect(find.textContaining('verifica la connessione'), findsOneWidget);
  });

  testWidgets('B45: zero is a real result and action is wired',
      (tester) async {
    var presses = 0;
    await tester.pumpWidget(app(count: 0, onTap: () => presses++));
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.text('ANALIZZA LE PARTITE'));
    expect(presses, 1);
  });
}
