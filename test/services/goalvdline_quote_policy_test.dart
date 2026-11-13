import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_quote_policy.dart';

void main() {
  test('P20.6 Sisal-only: rifiuta bookmaker diversi', () {
    expect(GoalVdLineQuotePolicy.isSisal('Sisal'), true);
    expect(GoalVdLineQuotePolicy.isSisal('SISAL IT'), true);
    expect(GoalVdLineQuotePolicy.isSisal('Bet365'), false);
    expect(GoalVdLineQuotePolicy.isSisal('Not Sisal'), false);
  });
  test('P20.6 quota minima 1,20 inclusa; nessuna quota inventata', () {
    expect(GoalVdLineQuotePolicy.isPlayable(1.20), true);
    expect(GoalVdLineQuotePolicy.isPlayable(1.19), false);
    expect(GoalVdLineQuotePolicy.isPlayable(null), false);
    expect(GoalVdLineQuotePolicy.isPlayable(double.infinity), false);
    expect(GoalVdLineQuotePolicy.isPlayable(double.nan), false);
  });
}
