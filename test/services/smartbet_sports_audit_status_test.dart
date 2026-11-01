import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';

void main() {
  AnalysisResult sample({String status = 'NOT_RUN'}) {
    return AnalysisResult(
      smartScore: 80,
      homeProbability: 65,
      drawProbability: 20,
      awayProbability: 15,
      prediction: '1',
      valueBet: '',
      risk: 'Basso',
      explanation: '',
      sportsAuditStatus: status,
    );
  }

  test('Analisi non verificata non equivale a confermata', () {
    final result = sample();
    expect(result.hasVerifiedSportsAudit, isFalse);
    expect(result.hasSportsAuditVeto, isFalse);
  });

  test('Forte contraddizione genera veto sportivo', () {
    final result = sample(status: 'STRONG_CONTRADICTION');
    expect(result.hasVerifiedSportsAudit, isTrue);
    expect(result.hasSportsAuditVeto, isTrue);
  });

  test('Conferma e dubbio sono distinti dal veto', () {
    for (final status in ['CONFIRM', 'DOUBT']) {
      final result = sample(status: status);
      expect(result.hasVerifiedSportsAudit, isTrue);
      expect(result.hasSportsAuditVeto, isFalse);
    }
  });

  test('Auditor saltato non risulta verificato', () {
    final result = sample(status: 'SKIPPED_FAST');
    expect(result.hasVerifiedSportsAudit, isFalse);
    expect(result.hasSportsAuditVeto, isFalse);
  });
}
