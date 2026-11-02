import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_diagnostic_export_service.dart';

void main() {
  Map<String, dynamic> sample({
    List<Map<String, dynamic>> markets = const [],
    List<Map<String, dynamic>> shadow = const [],
    List<Map<String, dynamic>> scorers = const [],
  }) => SmartBetDiagnosticPayloadBuilder.build(
    generatedAt: DateTime.utc(2026, 11, 2),
    learningEnabled: true,
    markets: markets,
    comparisons: const [],
    shadow: shadow,
    snapshots: const [],
    scorers: scorers,
    savedPredictions: const [],
  );

  test('non inventa valutazioni quando gli storici sono vuoti', () {
    final report = sample();
    expect(report['schema'], 'smartbet-diagnostica-v1');
    expect(report['learningEnabledOnThisDevice'], isTrue);
    expect((report['summary'] as Map)['marketPredictions'], 0);
    expect((report['shadowBrierOnMatchedVerified'] as Map)['original'], isNull);
    expect((report['data'] as Map).containsKey('apiKeys'), isFalse);
  });

  test('mercati verificati: distingue errori e probabilita originali', () {
    final report = sample(
      markets: [
        {
          'engine': 'smartBet',
          'fixtureId': 17,
          'market': 'Over 2.5',
          'prospectiveEligible': true,
          'status': 'wrong',
          'probability': 0.8,
          'quotedOdd': 1.5,
        },
        {
          'engine': 'smartBet',
          'fixtureId': 18,
          'market': 'Over 2.5',
          'prospectiveEligible': true,
          'status': 'correct',
          'probability': 0.6,
        },
        {
          'engine': 'smartBet',
          'fixtureId': 19,
          'market': 'Over 2.5',
          'prospectiveEligible': false,
          'status': 'correct',
          'probability': 0.9,
        },
      ],
    );
    final summary = report['summary'] as Map;
    expect(summary['marketProspectiveVerified'], 2);
    expect(summary['marketProspectiveWrong'], 1);
    final over = (report['byMarket'] as List).single as Map;
    expect(over['observedFrequency'], 0.5);
    expect(over['averageOriginalProbability'], closeTo(0.7, 0.0001));
  });

  test('shadow: compara brier solo per previsioni verificate', () {
    final report = sample(
      markets: [
        {
          'engine': 'smartBet',
          'fixtureId': 17,
          'market': 'Over 2.5',
          'prospectiveEligible': true,
          'status': 'wrong',
          'probability': 0.8,
        },
      ],
      shadow: [
        {
          'key': 'smartBet|17|Over 2.5',
          'originalProbability': 0.8,
          'calibratedProbability': 0.6,
        },
        {
          'key': 'smartBet|99|Over 2.5',
          'originalProbability': 0.8,
          'calibratedProbability': 0.1,
        },
      ],
    );
    final brier = report['shadowBrierOnMatchedVerified'] as Map;
    expect(brier['sampleSize'], 1);
    expect(brier['original'], closeTo(0.64, 0.00001));
    expect(brier['calibrated'], closeTo(0.36, 0.00001));
  });
}
