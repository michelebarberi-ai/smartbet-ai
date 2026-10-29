import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_european_handicap_candidate_service.dart';

void main() {
  List<({String market, int probability})> calculate(
    Iterable<String> markets, {
    double home = 1.7,
    double away = 1.1,
  }) {
    return SmartBetEuropeanHandicapCandidateService.candidates(
      expectedHomeGoals: home,
      expectedAwayGoals: away,
      quotedOutcomes: markets,
    );
  }

  test('accetta soltanto linee quotate', () {
    final result = calculate(['HCP EURO CASA -1 1', 'HCP EURO CASA -1 X']);

    expect(result.length, 2);
    expect(result.map((e) => e.market).toSet(), {
      'HCP EURO CASA -1 1',
      'HCP EURO CASA -1 X',
    });
  });

  test('non interpreta handicap asiatici', () {
    expect(calculate(['ASIAN HANDICAP HOME -0.75']), isEmpty);
  });

  test('scarta formati e linee non supportati', () {
    expect(
      calculate([
        'HCP EURO CASA -0.5 1',
        'HCP EURO CASA -99 1',
        'HCP EURO CASA -1 Y',
      ]),
      isEmpty,
    );
  });

  test('non duplica esiti identici', () {
    expect(calculate(['HCP EURO CASA -1 X', 'HCP EURO CASA -1 X']).length, 1);
  });

  test('non genera candidati senza goal attesi validi', () {
    expect(calculate(['HCP EURO CASA -1 1'], home: 0), isEmpty);
  });

  test('probabilita in intervallo valido', () {
    final result = calculate([
      'HCP EURO CASA -1 1',
      'HCP EURO CASA -1 X',
      'HCP EURO CASA -1 2',
    ]);

    expect(result.length, 3);

    final total = result.fold<int>(0, (sum, item) => sum + item.probability);

    expect(total, inInclusiveRange(99, 101));
  });
}
