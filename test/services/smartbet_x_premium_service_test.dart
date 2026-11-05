import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/smartbet_x_premium_service.dart';

AnalysisResult analysis({
  double homeXg = 1.1,
  double awayXg = 1.1,
  int dataConfidence = 80,
  int home = 35,
  int draw = 30,
  int away = 35,
}) => AnalysisResult(
  smartScore: 75,
  dataConfidence: dataConfidence,
  homeProbability: home,
  drawProbability: draw,
  awayProbability: away,
  expectedHomeGoals: homeXg,
  expectedAwayGoals: awayXg,
  prediction: 'X',
  valueBet: '',
  risk: '',
  explanation: '',
);

void main() {
  const service = SmartBetXPremiumService();

  test('X Premium calcola la X senza quote, da gol attesi validi', () {
    final item = service.assess(fixtureId: 10, analysis: analysis());
    expect(item.simulatedDraw, isNotNull);
    expect(item.simulatedDraw!, inInclusiveRange(0, 1));
    expect(item.nativeDraw, 0.30);
    expect(item.dataQuality, 0.80);
    expect(item.alternatives, isNotEmpty);
  });

  test('non inventa xG se mancano: mostra la partita non simulabile', () {
    final item = service.assess(fixtureId: 11, analysis: analysis(homeXg: 0));
    expect(item.simulatedDraw, isNull);
    expect(item.priority, isFalse);
    expect(item.reason, contains('non simulabile'));
  });

  test('la qualita non misurata non diventa 100%', () {
    final item = service.assess(
      fixtureId: 12,
      analysis: analysis(dataConfidence: 0),
    );
    expect(item.simulatedDraw, isNotNull);
    expect(item.dataQuality, isNull);
    expect(item.priority, isFalse);
    expect(item.reason, contains('non misurata'));
  });

  test('la bassa qualita non viene classificata come prioritaria', () {
    final item = service.assess(
      fixtureId: 13,
      analysis: analysis(dataConfidence: 40),
    );
    expect(item.priority, isFalse);
  });

  test('senza 1X2 valide non attribuisce una quota nativa X', () {
    final item = service.assess(
      fixtureId: 14,
      analysis: analysis(home: 0, draw: 0, away: 0),
    );
    expect(item.nativeDraw, isNull);
    expect(item.simulatedDraw, isNotNull);
  });

  test('ranking conserva ogni fixture, anche quelle senza simulazione', () {
    final available = service.assess(fixtureId: 15, analysis: analysis());
    final missing = SmartBetXPremiumAssessment.unavailable(fixtureId: 16);
    final ranked = service.rank([missing, available]);
    expect(ranked, hasLength(2));
    expect(ranked.first.fixtureId, 15);
    expect(ranked.last.fixtureId, 16);
  });

  test('ranking rifiuta fixture duplicate', () {
    final item = service.assess(fixtureId: 17, analysis: analysis());
    expect(() => service.rank([item, item]), throwsArgumentError);
  });

  test('classifica una X sopra soglia con dati misurati di qualita', () {
    final item = service.assess(
      fixtureId: 18,
      analysis: analysis(homeXg: 0.65, awayXg: 0.65),
    );
    expect(item.simulatedDraw, greaterThanOrEqualTo(0.30));
    expect(item.priority, isTrue);
  });

  test('non accetta id partita non validi', () {
    expect(
      () => service.assess(fixtureId: 0, analysis: analysis()),
      throwsArgumentError,
    );
  });
}
