import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfileStore extends ChangeNotifier {
  UserProfileStore._();

  static final UserProfileStore instance = UserProfileStore._();

  static const String _nameKey = 'smartbet_user_name';

  bool _initialized = false;
  bool _initializing = false;
  String _name = '';

  String get name => _name.trim();

  Future<void> initialize() async {
    if (_initialized || _initializing) return;

    _initializing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _name = (prefs.getString(_nameKey) ?? '').trim();
      _initialized = true;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> setName(String value) async {
    final cleaned = value.trim();
    final prefs = await SharedPreferences.getInstance();

    _name = cleaned;
    _initialized = true;

    if (cleaned.isEmpty) {
      await prefs.remove(_nameKey);
    } else {
      await prefs.setString(_nameKey, cleaned);
    }

    notifyListeners();
  }
}
