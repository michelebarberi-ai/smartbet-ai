import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_ai_service.dart';

void main() {
  SmartBetFeasibilityAudit audit(String status) {
    return SmartBetFeasibilityAudit(
      status: status,
      reasons: const [],
      missingFactors: const [],
      blockedMarkets: const [],
    );
  }

  test('Fallback neutro non equivale ad approvazione', () {
    expect(SmartBetFeasibilityAudit.neutral.status, 'NOT_RUN');
    expect(SmartBetFeasibilityAudit.neutral.isConfirmed, isFalse);
  });

  test('Stati non verificati non sono confermati', () {
    for (final status in [
      'NOT_RUN',
      'SKIPPED_FAST',
      'UNAVAILABLE',
      'UNKNOWN',
    ]) {
      expect(audit(status).isConfirmed, isFalse);
    }
  });

  test('Solo CONFIRM equivale ad approvazione', () {
    expect(audit('CONFIRM').isConfirmed, isTrue);
    expect(audit('DOUBT').isConfirmed, isFalse);
    expect(audit('STRONG_CONTRADICTION').isConfirmed, isFalse);
  });

  test('Il veto sportivo rimane operativo', () {
    final result = audit('STRONG_CONTRADICTION');
    expect(result.isBlocked, isTrue);
    expect(result.isConfirmed, isFalse);
  });
}
