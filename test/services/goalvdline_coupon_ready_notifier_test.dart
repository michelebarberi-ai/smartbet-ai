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

  test('B49: iOS lock screen status is read independently of opt-in', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getNotificationStatus') {
        return <String, Object>{
          'authorization': 'authorized',
          'lockScreen': false,
          'alerts': true,
          'notificationCenter': true,
        };
      }
      return null;
    });
    final status = await notifier.notificationStatus();
    expect(status, isNotNull);
    expect(status!.isAllowed, true);
    expect(status.lockScreen, false);
    expect(status.italianSummary, contains('Schermo bloccato'));
  });

  test('B49: denied iOS authorization is not reported as enabled', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object>{
        'authorization': 'denied',
        'lockScreen': false,
        'alerts': false,
        'notificationCenter': false,
      };
    });
    final status = await notifier.notificationStatus();
    expect(status!.isAllowed, false);
    expect(status.italianSummary, contains('negato'));
  });

  test('B49: locked screen test needs opt-in and reports native schedule', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    expect(await notifier.sendLockScreenTestNotification(), false);
    expect(calls, isEmpty);
    expect(await notifier.setEnabled(true), true);
    expect(await notifier.sendLockScreenTestNotification(), true);
    expect(calls, ['requestPermission', 'sendLockScreenTestNotification']);
  });

  test('B49: absent iOS handler does not claim lock test or status', () async {
    expect(await notifier.notificationStatus(), isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(GoalVdLineCouponReadyNotifier.storageKey, true);
    expect(await notifier.sendLockScreenTestNotification(), false);
  });

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

  test('QA: test notification needs consent but not a completed coupon',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    expect(await notifier.sendTestNotification(), false);
    expect(calls, isEmpty);
    expect(await notifier.setEnabled(true), true);
    expect(await notifier.sendTestNotification(), true);
    expect(calls, ['requestPermission', 'sendTestNotification']);
  });

  test('QA: native test failure is reported but does not disable preference',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermission') return true;
      throw PlatformException(code: 'notifications_disabled');
    });
    expect(await notifier.setEnabled(true), true);
    expect(await notifier.sendTestNotification(), false);
    expect(await notifier.isEnabled(), true);
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
