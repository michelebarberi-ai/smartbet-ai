import 'package:flutter/services.dart';

/// Notifies ONLY after an on-demand generation has finished with actual picks.
/// Native iOS local notification; no APNs, scheduler, server or daily job.
/// A notification is never sent when zero events passed the quality checks.
class GoalVdLineRequestedCouponNotification {
  const GoalVdLineRequestedCouponNotification();

  static const MethodChannel _channel =
      MethodChannel('goalvdline/requested_coupon_notifications');

  Future<bool> notifyReady({required int eventCount}) async {
    if (eventCount < 1 || eventCount > 15) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'notifyReady',
            <String, Object>{'eventCount': eventCount},
          ) ??
          false;
    } on MissingPluginException {
      // Android, macOS and Flutter tests may not install this iOS channel.
      return false;
    } on PlatformException {
      // Notification authorization cannot block or invalidate the coupon.
      return false;
    }
  }
}
