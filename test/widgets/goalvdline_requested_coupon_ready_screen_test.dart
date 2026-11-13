import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/screens/goalvdline_requested_coupon_ready_screen.dart';
import 'package:smartbet_ai_new/services/goalvdline_ready_coupon_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('B45 local tap shows last completed fixture and market',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      GoalVdLineReadyCouponLocalStore.key:
          'CORE — 3 partite\n1. Torino - Udinese | 1X | 78% | quota 1.30',
    });
    await tester.pumpWidget(const MaterialApp(
      home: GoalVdLineRequestedCouponReadyScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b45-local-ready-summary')), findsOneWidget);
    final summary = tester.widget<SelectableText>(
      find.byKey(const Key('b45-local-ready-summary')),
    );
    expect(summary.data, contains('Torino - Udinese'));
  });

  testWidgets('B45 local tap never invents missing results', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(
      home: GoalVdLineRequestedCouponReadyScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nessuna schedina completata'), findsOneWidget);
  });
}
