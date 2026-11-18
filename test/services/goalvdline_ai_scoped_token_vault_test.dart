import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_ai_scoped_token_vault.dart';
import 'package:smartbet_ai_new/services/goalvdline_mobile_token_vault.dart';

void main() {
  test('AI e learning usano chiavi Portachiavi diverse', () {
    expect(
      GoalVdLineAiScopedTokenVault.storageKey,
      isNot(GoalVdLineMobileTokenVault.storageKey),
    );
    expect(GoalVdLineAiScopedTokenVault.storageKey, contains('ai_scoped'));
  });

  test('non memorizza mai un token che non dichiara ai:analyze', () async {
    final vault = GoalVdLineAiScopedTokenVault();
    await expectLater(
      vault.saveScopedToken(
        token: 'a' * 43,
        serverReportedScopes: 'learning:predictions',
      ),
      throwsFormatException,
    );
    await expectLater(
      vault.saveScopedToken(
        token: 'a' * 43,
        serverReportedScopes: 'learning:predictions ai:analyzeExtra',
      ),
      throwsFormatException,
    );
  });

  test('non accetta token AI di forma invalida, anche con permessi', () async {
    final vault = GoalVdLineAiScopedTokenVault();
    await expectLater(
      vault.saveScopedToken(
        token: 'bad-token',
        serverReportedScopes: 'learning:predictions ai:analyze',
      ),
      throwsFormatException,
    );
  });
}
