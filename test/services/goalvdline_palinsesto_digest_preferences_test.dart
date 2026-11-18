import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_palinsesto_digest_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('B72: daily digest starts OFF at 08:00, distinct from coupons', () async {
    const store = GoalVdLinePalinsestoDigestPreferencesStore();
    final value = await store.load();
    expect(value.requested, isFalse);
    expect(value.formattedHour, '08:00');
    expect(GoalVdLinePalinsestoDigestPreferencesStore.storageKey,
        isNot('goalvdline_auto_coupon_preferences_v1'));
  });

  test('B72: 07:35 notification preference persists without enabling coupon', () async {
    const store = GoalVdLinePalinsestoDigestPreferencesStore();
    final value = const GoalVdLinePalinsestoDigestPreferences()
        .copyWith(requested: true, hour: 7, minute: 35);
    expect(await store.save(value), isTrue);
    final loaded = await store.load();
    expect(loaded.requested, isTrue);
    expect(loaded.formattedHour, '07:35');
  });

  test('B72: saved morning digest never alters automatic coupon preference', () async {
    SharedPreferences.setMockInitialValues({
      'goalvdline_auto_coupon_preferences_v1': jsonEncode({'requested': false}),
    });
    const store = GoalVdLinePalinsestoDigestPreferencesStore();
    await store.save(const GoalVdLinePalinsestoDigestPreferences(requested:true));
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString('goalvdline_auto_coupon_preferences_v1')!)
          ['requested'], isFalse);
  });

  test('B72: invalid local data does not silently enable morning push', () async {
    SharedPreferences.setMockInitialValues({
      GoalVdLinePalinsestoDigestPreferencesStore.storageKey:
          jsonEncode({'requested': true, 'hour': 31, 'minute': 55}),
    });
    final loaded =
        await const GoalVdLinePalinsestoDigestPreferencesStore().load();
    expect(loaded.requested, isFalse);
    expect(loaded.formattedHour, '08:00');
    expect(const GoalVdLinePalinsestoDigestPreferences(minute: 60).isValid,
        isFalse);
  });
}
