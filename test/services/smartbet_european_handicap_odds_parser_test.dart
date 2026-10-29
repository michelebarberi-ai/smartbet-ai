import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_european_handicap_odds_parser.dart';

void main() {
  String? parse(int id, String value) {
    return SmartBetEuropeanHandicapOddsParser.outcomeFor(
      betId: id,
      value: value,
    );
  }

  test('Home -1 diventa segno 1 handicap casa -1', () {
    expect(parse(9, 'Home -1'), 'HCP EURO CASA -1 1');
  });

  test('Draw -1 diventa segno X handicap casa -1', () {
    expect(parse(9, 'Draw -1'), 'HCP EURO CASA -1 X');
  });

  test('Away -1 diventa segno 2 handicap casa -1', () {
    expect(parse(9, 'Away -1'), 'HCP EURO CASA -1 2');
  });

  test('supporta anche handicap positivo', () {
    expect(parse(9, 'Home +2'), 'HCP EURO CASA 2 1');
    expect(parse(9, 'Draw +1'), 'HCP EURO CASA 1 X');
  });

  test('non confonde handicap asiatico ID 4', () {
    expect(parse(4, 'Home -1'), isNull);
    expect(parse(4, 'Away -0.75'), isNull);
  });

  test('non confonde handicap primo tempo ID 18', () {
    expect(parse(18, 'Home -1'), isNull);
    expect(parse(19, 'Away -1'), isNull);
  });

  test('non confonde corner e cartellini', () {
    expect(parse(56, 'Home +0'), isNull);
    expect(parse(79, 'Draw +0'), isNull);
    expect(parse(81, 'Away +0'), isNull);
    expect(parse(239, 'Home +1'), isNull);
  });

  test('rifiuta linee decimali e fuori limite', () {
    expect(parse(9, 'Home -0.5'), isNull);
    expect(parse(9, 'Draw -99'), isNull);
    expect(parse(9, 'Away +6'), isNull);
  });

  test('rifiuta valori non riconosciuti', () {
    expect(parse(9, 'Something -1'), isNull);
    expect(parse(9, 'Home'), isNull);
  });
}
