import 'dart:async';

/// Serializes requests launched by different analysis batches on the same
/// iPhone. The previous timestamp-only implementation let concurrent callers
/// wake together and create bursts, despite its 250 ms intended spacing.
///
/// The server still enforces its own shared provider limits across devices.
class ApiRateLimiter {
  ApiRateLimiter._();

  // Stay comfortably below five requests/second from this client. This is
  // only a local pacing rule; it does not guarantee upstream quota availability.
  static const Duration _minimumDelay = Duration(milliseconds: 400);

  static DateTime? _lastRequestTime;
  static Future<void> _queue = Future<void>.value();

  static Future<void> wait() {
    // Chaining futures reserves the slot synchronously, before any await.
    // This prevents parallel SmartCore/league analyses sharing a wake-up.
    final next = _queue.then((_) async {
      final last = _lastRequestTime;
      if (last != null) {
        final remaining = _minimumDelay - DateTime.now().difference(last);
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }
      _lastRequestTime = DateTime.now();
    });
    _queue = next;
    return next;
  }
}
