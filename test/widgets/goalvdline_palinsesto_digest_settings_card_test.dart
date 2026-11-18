import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/widgets/goalvdline_palinsesto_digest_settings_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('B72: morning schedule is presented without daily coupon', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: GoalVdLinePalinsestoDigestSettingsCard(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Riepilogo quotidiano del palinsesto'), findsOneWidget);
    expect(find.byKey(const Key('b72-daily-fixture-digest-time')), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.textContaining('non attiva ancora la notifica push'), findsOneWidget);
    expect(find.textContaining('Non genera automaticamente schedine'), findsOneWidget);
    expect(find.text('Desidero una schedina ogni giorno'), findsNothing);
  });
}
