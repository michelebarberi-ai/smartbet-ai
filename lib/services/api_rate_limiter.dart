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
  static DateTime? _providerCooldownUntil;

  /// Shared by local analysis services; never treat an outage as "no odds".
  static bool get isCoolingDown {
    final until = _providerCooldownUntil;
    if (until == null) return false;
    if (!DateTime.now().isBefore(until)) {
      _providerCooldownUntil = null;
      return false;
    }
    return true;
  }

  /// An HTTP 200 with the provider's rate-limit error is translated by
  /// Render to an explicit machine code; respect that code and Retry-After.
  static void noteProviderResponse({
    required int statusCode,
    required String body,
    String? retryAfter,
  }) {
    if (statusCode != 429 &&
        !body.contains('FOOTBALL_PROVIDER_RATE_LIMIT') &&
        !body.contains('FOOTBALL_PROVIDER_COOLDOWN')) {
      return;
    }
    final seconds = (int.tryParse(retryAfter ?? '') ?? 120)
        .clamp(30, 1800)
        .toInt();
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    if (_providerCooldownUntil == null ||
        deadline.isAfter(_providerCooldownUntil!)) {
      _providerCooldownUntil = deadline;
    }
  }

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
