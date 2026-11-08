import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_mobile_token_vault.dart';

void main() {
  test('il Portachiavi accetta solo i token mobile da 43 caratteri', () {
    expect(
      GoalVdLineMobileTokenVault.validToken(List.filled(43, 'a').join()),
      true,
    );
    expect(
      GoalVdLineMobileTokenVault.validToken(List.filled(42, 'a').join()),
      false,
    );
    expect(
      GoalVdLineMobileTokenVault.validToken(List.filled(44, 'a').join()),
      false,
    );
    expect(
      GoalVdLineMobileTokenVault.validToken('${List.filled(42, 'a').join()}!'),
      false,
    );
  });
}
