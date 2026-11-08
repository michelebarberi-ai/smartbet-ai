import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Conserva esclusivamente la credenziale MOBILE nel Portachiavi iOS.
/// Nessun token amministratore deve mai essere salvato nell'app.
class GoalVdLineMobileTokenVault {
  GoalVdLineMobileTokenVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'goalvdline_learning_mobile_token_v1';
  static final _pattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
  final FlutterSecureStorage _storage;

  static bool validToken(String value) => _pattern.hasMatch(value.trim());

  Future<String?> read() async {
    final token = await _storage.read(key: _key);
    if (token == null) return null;
    if (validToken(token)) return token;
    // Una credenziale corrotta non deve essere usata per effettuare richieste.
    await _storage.delete(key: _key);
    return null;
  }

  Future<void> save(String token) async {
    final value = token.trim();
    if (!validToken(value)) {
      throw const FormatException('Token mobile non valido');
    }
    await _storage.write(
      key: _key,
      value: value,
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.unlocked,
        synchronizable: false,
      ),
    );
  }

  Future<void> delete() => _storage.delete(key: _key);
}
