import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_daily_matches_card.dart';

void main() {
  Widget app({required int? count, int? totalCount, bool loading = false, VoidCallback? onTap}) =>
      MaterialApp(
        home: Scaffold(
          body: GoalVdLineDailyMatchesCard(
            count: count,
            totalCount: totalCount,
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
    expect(find.textContaining('12 partite future compatibili'), findsOneWidget);
    expect(find.textContaining('non significa'), findsOneWidget);
  });

  testWidgets('B63: Home explains filtered count versus all upcoming fixtures',
      (tester) async {
    await tester.pumpWidget(app(count: 14, totalCount: 57));
    expect(find.text('14'), findsOneWidget);
    expect(find.textContaining('Totale incontri futuri nel feed di oggi: 57'),
        findsOneWidget);
    expect(find.textContaining('Palinsesto Italia'), findsWidgets);
    expect(find.textContaining('filtro indicativo'), findsOneWidget);
    expect(find.textContaining('quota reale'), findsOneWidget);
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
