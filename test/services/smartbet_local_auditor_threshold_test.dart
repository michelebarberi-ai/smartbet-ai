import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/smartbet_local_auditor.dart';

AnalysisResult sample({
  String sportsStatus = 'SKIPPED_FAST',
  List<String> blocked = const [],
}) => AnalysisResult(
  smartScore: 78,
  sportsAuditStatus: sportsStatus,
  sportsAuditBlockedMarkets: blocked,
  homeProbability: 65,
  drawProbability: 20,
  awayProbability: 15,
  prediction: 'OVER 1.5',
  valueBet: '',
  risk: 'MEDIO',
  explanation: 'Test auditor locale',
);

void main() {
  test('B47: quota 1.20 esclusa, 1.21 e 1.24 ammesse', () {
    final analysis = sample();
    for (final odd in [1.19, 1.20]) {
      final audit = SmartBetLocalAuditor.evaluate(
        analysis: analysis,
        market: 'OVER 1.5',
        probability: 78,
        odd: odd,
      );
      expect(audit.isBlocked, true, reason: 'Quota $odd');
    }
    for (final odd in [1.21, 1.24, 1.25]) {
      final audit = SmartBetLocalAuditor.evaluate(
        analysis: analysis,
        market: 'OVER 1.5',
        probability: 78,
        odd: odd,
      );
      expect(audit.isBlocked, false, reason: 'Quota $odd');
    }
  });

  test('B47: quote non finite e zero rimangono bloccate', () {
    for (final odd in [0.0, double.nan, double.infinity]) {
      final audit = SmartBetLocalAuditor.evaluate(
        analysis: sample(),
        market: 'GOAL',
        probability: 80,
        odd: odd,
      );
      expect(audit.isBlocked, true);
    }
  });

  test('B47: veto remoto e mercati bloccati prevalgono sulla quota', () {
    final veto = SmartBetLocalAuditor.evaluate(
      analysis: sample(sportsStatus: 'STRONG_CONTRADICTION'),
      market: 'OVER 1.5',
      probability: 87,
      odd: 1.75,
    );
    expect(veto.isBlocked, true);
    final marketBlocked = SmartBetLocalAuditor.evaluate(
      analysis: sample(blocked: ['goal']),
      market: 'GOAL',
      probability: 87,
      odd: 1.75,
    );
    expect(marketBlocked.isBlocked, true);
    final other = SmartBetLocalAuditor.evaluate(
      analysis: sample(blocked: ['goal']),
      market: 'OVER 1.5',
      probability: 87,
      odd: 1.75,
    );
    expect(other.isBlocked, false);
  });
}
