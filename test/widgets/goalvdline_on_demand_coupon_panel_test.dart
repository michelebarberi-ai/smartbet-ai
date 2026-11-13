import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_on_demand_coupon_client.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_on_demand_coupon_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(WidgetTester tester, bool enabled) async {
    final remote = GoalVdLineOnDemandCouponClient(
      client: MockClient((request) async {
        expect(request.url.path, '/learning/v1/status');
        return http.Response(jsonEncode({
          'enabled': true,
          'mobileIngestEnabled': true,
          'onDemandCouponRequestsEnabled': enabled,
        }), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GoalVdLineOnDemandCouponPanel(
          events: 5,
          minimumProbability: 65,
          client: remote,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('B47: the remote coupon panel fails closed when server is OFF',
      (tester) async {
    await mount(tester, false);
    expect(find.text('ELABORAZIONE SERVER · BETA'), findsNothing);
    expect(find.text('CREA SUL SERVER'), findsNothing);
  });

  testWidgets('B47: server opt-in shows separate action, not an automatic job',
      (tester) async {
    await mount(tester, true);
    expect(find.text('ELABORAZIONE SERVER · BETA'), findsOneWidget);
    expect(find.text('CREA SUL SERVER'), findsOneWidget);
    expect(find.text('RECUPERA RISULTATO'), findsOneWidget);
  });
}
