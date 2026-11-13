import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_coupon_ready_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifier = GoalVdLineCouponReadyNotifier();
  const channel = GoalVdLineCouponReadyNotifier.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, null);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('B45: notifications disabled by default and no native call', () async {
    var called = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called++;
      return true;
    });
    expect(await notifier.isEnabled(), false);
    expect(await notifier.notifyReady(coupons: 3, fixturesInPrimary: 5), false);
    expect(called, 0);
  });

  test('B45: explicit opt-in allows only completed coupons', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    expect(await notifier.setEnabled(true), true);
    expect(await notifier.isEnabled(), true);
    expect(await notifier.notifyReady(coupons: 0, fixturesInPrimary: 5), false);
    expect(await notifier.notifyReady(coupons: 3, fixturesInPrimary: 0), false);
    expect(await notifier.notifyReady(coupons: 3, fixturesInPrimary: 5), true);
    expect(calls.map((c) => c.method).toList(),
        ['requestPermission', 'notifyReady']);
    expect(calls.last.arguments, {'coupons': 3, 'fixtures': 5});
    await notifier.setEnabled(false);
    expect(await notifier.isEnabled(), false);
    expect(await notifier.notifyReady(coupons: 1, fixturesInPrimary: 5), false);
    expect(calls.length, 2);
  });

  test('B45: refused permission never enables or sends notifications', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return false;
    });
    expect(await notifier.setEnabled(true), false);
    expect(await notifier.isEnabled(), false);
    expect(await notifier.notifyReady(coupons: 1, fixturesInPrimary: 3), false);
    expect(calls, 1);
  });

  test('B45: missing native handler is nonfatal and never enables', () async {
    expect(await notifier.setEnabled(true), false);
    expect(await notifier.isEnabled(), false);
    expect(await notifier.notifyReady(coupons: 1, fixturesInPrimary: 5), false);
  });

  test('B45: native failure is not treated as coupon failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermission') return true;
      throw PlatformException(code: 'unavailable');
    });
    expect(await notifier.setEnabled(true), true);
    expect(await notifier.notifyReady(coupons: 1, fixturesInPrimary: 5), false);
  });
}
