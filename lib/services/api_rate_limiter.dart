class ApiRateLimiter {
  ApiRateLimiter._();

  static const Duration _minimumDelay =
      Duration(milliseconds: 250);

  static DateTime? _lastRequestTime;

  static Future<void> wait() async {
    final now = DateTime.now();

    if (_lastRequestTime != null) {
      final elapsed =
          now.difference(_lastRequestTime!);

      final remaining =
          _minimumDelay - elapsed;

      if (!remaining.isNegative) {
        await Future.delayed(remaining);
      }
    }

    _lastRequestTime = DateTime.now();
  }
}