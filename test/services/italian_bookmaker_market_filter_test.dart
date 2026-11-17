import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/italian_bookmaker_market_filter.dart';

void main() {
  test('B63: nomi bookmaker presenti in Italia sono controllati solo a valle', () {
    expect(ItalianBookmakerMarketFilter.appearsInItalianMarket('Sisal'), isTrue);
    expect(ItalianBookmakerMarketFilter.appearsInItalianMarket('Bet365'), isTrue);
    expect(ItalianBookmakerMarketFilter.appearsInItalianMarket('Betfair'), isTrue);
    expect(ItalianBookmakerMarketFilter.appearsInItalianMarket('Pinnacle'), isFalse);
    expect(ItalianBookmakerMarketFilter.appearsInItalianMarket(''), isFalse);
  });
}
