import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/smartbet_multimarket_ranking_service.dart';

AnalysisResult analysis({double h = 1.5, double a = 1.1, int quality = 80}) =>
    AnalysisResult(
      smartScore: 65,
      homeProbability: 42,
      drawProbability: 29,
      awayProbability: 29,
      expectedHomeGoals: h,
      expectedAwayGoals: a,
      dataConfidence: quality,
      prediction: 'X',
      valueBet: '',
      risk: '',
      explanation: '',
    );

void main() {
  const ranker = SmartBetMultiMarketRankingService();
  test('P21K: restituisce anche le fixture senza dati', () {
    final ranked = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(fixtureId: 1, analysis: analysis()),
        const SmartBetMultiMarketFixture(fixtureId: 2, analysis: null),
      ],
      families: ['1X2'],
    );
    expect(ranked.length, 2);
    expect(ranked.last.fixtureId, 2);
    expect(ranked.last.band, SmartBetFixtureBand.insufficientData);
  });
  test('P21K: non inventa un pronostico con xG mancanti', () {
    final ranked = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(fixtureId: 2, analysis: analysis(h: 0)),
      ],
      families: ['GOAL'],
    );
    expect(ranked.single.selection, isNull);
  });
  test('P21K: rispetta la famiglia X senza introdurre Over', () {
    final ranked = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(fixtureId: 4, analysis: analysis()),
      ],
      families: ['1X2'],
    );
    expect(['1', 'X', '2'], contains(ranked.single.selection!.market));
    expect(
      ranked.single.alternatives.every(
        (x) => ['1', 'X', '2'].contains(x.market),
      ),
      isTrue,
    );
  });
  test('P21K: permette fino a 3 famiglie, blocca la quarta', () {
    final selected = [
      SmartBetMultiMarketFixture(fixtureId: 5, analysis: analysis()),
    ];
    expect(
      ranker
          .rank(
            selectedMatches: selected,
            families: ['OVER', 'GOAL', 'DOPPIA CHANCE'],
          )
          .length,
      1,
    );
    expect(
      () => ranker.rank(
        selectedMatches: selected,
        families: ['OVER', 'GOAL', 'UNDER', '1X2'],
      ),
      throwsArgumentError,
    );
  });
  test('B47: ranking multimercato include OR senza inventare quote', () {
    final ranked = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(fixtureId: 70, analysis: analysis()),
      ],
      families: ['OVER', 'GOAL', 'MERCATI OPPURE'],
    );
    final item = ranked.single;
    expect(item.familyLeaders.keys,
        containsAll(['OVER', 'GOAL', 'MERCATI OPPURE']));
    expect(item.familyLeaders['OVER']!.market, startsWith('OVER'));
    expect(item.familyLeaders['GOAL']!.market,
        anyOf('GOAL', 'NO GOAL'));
    expect(item.familyLeaders['MERCATI OPPURE']!.market,
        contains(' O '));
    for (final leader in item.familyLeaders.values) {
      expect(leader.probability, inInclusiveRange(0, 1));
      expect(leader.decimalOdd, isNull);
    }
    expect(item.selection!.probability, greaterThanOrEqualTo(0));
  });

  test('B47: una sola famiglia non mostra mercati estranei', () {
    final item = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(fixtureId: 71, analysis: analysis()),
      ],
      families: ['MERCATI OPPURE'],
    ).single;
    expect(item.selection!.market, contains(' O '));
    expect(item.familyLeaders.keys, ['MERCATI OPPURE']);
    expect(item.familyLeaders['MERCATI OPPURE']!.market,
        item.selection!.market);
  });

  test('P21K: blocca 16 partite', () {
    expect(
      () => ranker.rank(
        selectedMatches: List.generate(
          16,
          (i) => SmartBetMultiMarketFixture(
            fixtureId: i + 1,
            analysis: analysis(),
          ),
        ),
        families: [],
      ),
      throwsArgumentError,
    );
  });
  test('P21K: quote non alterano le probabilita sportive', () {
    final lowOdd = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(
          fixtureId: 9,
          analysis: analysis(),
          decimalOdds: const {'OVER 1.5': 1.21},
        ),
      ],
      families: ['OVER'],
    );
    final highOdd = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(
          fixtureId: 9,
          analysis: analysis(),
          decimalOdds: const {'OVER 1.5': 5.00},
        ),
      ],
      families: ['OVER'],
    );
    expect(
      lowOdd.single.selection!.probability,
      highOdd.single.selection!.probability,
    );
  });
  test('P21K: segnala margine valore separato', () {
    final ranked = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(
          fixtureId: 9,
          analysis: analysis(),
          decimalOdds: const {'OVER 1.5': 3.50},
        ),
      ],
      families: ['OVER'],
    );
    final option = [
      ranked.single.selection!,
      ...ranked.single.alternatives,
    ].firstWhere((v) => v.market == 'OVER 1.5');
    expect(option.expectedValueMargin, isNotNull);
    expect(option.decimalOdd, 3.5);
  });
  test('P21K: due fixture non vengono duplicate', () {
    expect(
      () => ranker.rank(
        selectedMatches: [
          SmartBetMultiMarketFixture(fixtureId: 42, analysis: analysis()),
          SmartBetMultiMarketFixture(fixtureId: 42, analysis: analysis()),
        ],
        families: ['1X2'],
      ),
      throwsArgumentError,
    );
  });
  test('P21K: nessun dato di quota implicita senza quota', () {
    final ranked = ranker.rank(
      selectedMatches: [
        SmartBetMultiMarketFixture(fixtureId: 10, analysis: analysis()),
      ],
      families: ['UNDER'],
    );
    expect(ranked.single.selection!.expectedValueMargin, isNull);
  });
}
