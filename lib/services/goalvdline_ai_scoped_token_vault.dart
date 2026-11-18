import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'goalvdline_mobile_token_vault.dart';

/// Separate storage for a server-issued AI-scoped device credential.
///
/// IMPORTANT: never fall back to the learning-only token; the backend must
/// check ai:analyze for every request. No admin secret is stored on the phone.
/// Provisioning is still an administrator-controlled, gated future workflow.
class GoalVdLineAiScopedTokenVault {
  GoalVdLineAiScopedTokenVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'goalvdline_ai_scoped_mobile_token_v1';
  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    final token = await _storage.read(key: storageKey);
    if (token == null) return null;
    if (GoalVdLineMobileTokenVault.validToken(token)) return token;
    await _storage.delete(key: storageKey);
    return null;
  }

  /// Call only after receiving a credential from the admin-only
  /// provision-ai endpoint with explicit ai:analyze scope.
  Future<void> saveScopedToken({
    required String token,
    required String serverReportedScopes,
  }) async {
    if (!serverReportedScopes.split(' ').contains('ai:analyze')) {
      throw const FormatException('Credenziale priva del permesso AI.');
    }
    final value = token.trim();
    if (!GoalVdLineMobileTokenVault.validToken(value)) {
      throw const FormatException('Token mobile AI non valido.');
    }
    await _storage.write(
      key: storageKey,
      value: value,
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.unlocked,
        synchronizable: false,
      ),
    );
  }

  Future<void> delete() => _storage.delete(key: storageKey);
}
