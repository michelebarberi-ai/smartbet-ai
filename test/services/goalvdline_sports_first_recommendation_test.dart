import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_sports_market_selector.dart';

void main() {
  test('P20.5 primary never changes when Sisal main odd is below 1.20', () {
    final result = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: {'1': 84, 'UNDER 3.5': 80, 'GOAL': 74, '2': 12},
      quotedOdds: {'1': 1.18, 'UNDER 3.5': 1.37, 'GOAL': 1.50, '2': 15},
      minimumProbability: 65,
    );
    expect(result, isNotNull);
    expect(result!.primary.market, '1');
    expect(result.primary.probability, 84);
    expect(result.primaryOdd, 1.18);
    expect(result.usesAlternative, isTrue);
    expect(result.couponPick!.market, 'UNDER 3.5');
    expect(result.couponPick!.probability, 80);
  });

  test('B47 1.21 is eligible and higher-priced odds do not change main', () {
    final result = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: {'1': 84, 'X': 70, '2': 10},
      quotedOdds: {'1': 1.21, 'X': 5, '2': 100},
    )!;
    expect(result.primary.market, '1');
    expect(result.couponPick!.market, '1');
    expect(result.usesAlternative, isFalse);
  });

  test('B47 1.20 exact is excluded without hiding top sporting forecast', () {
    final result = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: {'1': 84, 'X': 70, '2': 10},
      quotedOdds: {'1': 1.20, 'X': 5, '2': 100},
    )!;
    expect(result.primary.market, '1');
    expect(result.primaryOdd, 1.20);
    expect(result.couponPick!.market, 'X');
    expect(result.usesAlternative, isTrue);
  });

  test('P20.5 missing Sisal quotes retain main but never fabricate odds', () {
    final result = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: {'1': 84, 'OVER 2.5': 70},
      quotedOdds: {},
    )!;
    expect(result.primary.market, '1');
    expect(result.primaryOdd, isNull);
    expect(result.couponPick, isNull);
  });

  test('P20.5 rejects 7-13% alternatives despite large odds', () {
    final result = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: {'1': 88, 'X': 13, '2': 7},
      quotedOdds: {'1': 1.19, 'X': 16, '2': 30},
    )!;
    expect(result.primary.market, '1');
    expect(result.couponPick, isNull);
  });

  test('P20.5 quoted alternatives must be audited and at least 65%', () {
    final result = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: {'GOAL': 90, 'UNDER 2.5': 77, 'OVER 2.5': 74},
      quotedOdds: {'GOAL': 1.10, 'UNDER 2.5': 1.37, 'OVER 2.5': 1.33},
      blockedMarkets: ['UNDER 2.5'],
    )!;
    expect(result.primary.market, 'GOAL');
    expect(result.couponPick!.market, 'OVER 2.5');
    expect(result.couponPick!.probability, 74);
  });

  test('P20.5 invalid or low sports probabilities never become coupons', () {
    final result = SmartBetSportsMarketSelector.recommend(
      sportsProbabilities: {'1': 49, 'X': 35, '2': 16},
      quotedOdds: {'1': 1.60, 'X': 3.70, '2': 5.20},
    )!;
    expect(result.primary.market, '1');
    expect(result.couponPick, isNull);
  });
}
