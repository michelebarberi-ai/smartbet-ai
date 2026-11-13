import 'package:shared_preferences/shared_preferences.dart';

/// The latest user-requested, successfully generated coupon.
/// Local-only text snapshot. No auth tokens, device identifiers, background
/// tasks or server writes. A notification tap never regenerates predictions.
class GoalVdLineReadyCouponLocalStore {
  const GoalVdLineReadyCouponLocalStore();

  static const key = 'goalvdline_latest_requested_coupon_v1';
  static const maxLength = 32000;

  Future<bool> save(String summary) async {
    final value = summary.trim();
    if (value.isEmpty || value.length > maxLength) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(key);
      if (value == null || value.trim().isEmpty ||
          value.length > maxLength) return null;
      return value;
    } catch (_) {
      return null;
    }
  }
}
