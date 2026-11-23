import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/services/goalvdline_extra_markets_service.dart';
import 'package:smartbet_ai_new/services/goalvdline_extra_markets_odds_parser.dart';
import 'package:smartbet_ai_new/services/goalvdline_extra_market_result_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_market_settlement.dart';

AnalysisResult sample({double home = 1.8, double away = 0.9}) =>
    AnalysisResult(
      smartScore: 75, homeProbability: 55, drawProbability: 25,
      awayProbability: 20, expectedHomeGoals: home,
      expectedAwayGoals: away, prediction: '1', valueBet: '1',
      risk: 'medium', explanation: '',
    );

void main() {
  const service = GoalVdLineExtraMarketsService();
  const settlement = GoalVdLineExtraMarketResultService();

  test('B78: new families have explicit, distinct, canonical market IDs', () {
    final all = [
      ...GoalVdLineExtraMarketsService.firstHalfMarkets,
      ...GoalVdLineExtraMarketsService.secondHalfMarkets,
      ...GoalVdLineExtraMarketsService.cornerMarkets,
      ...GoalVdLineExtraMarketsService.shotsOnTargetMarkets,
    ];
    expect(all.toSet().length, all.length);
    expect(all.length, 30);
    for (final market in all) {
      expect(GoalVdLineExtraMarketsService.isExtraMarket(market), isTrue);
      expect(
        SmartBetAnalysisMarketSettlement.evaluate(
          market: market, homeGoals: 2, awayGoals: 1,
        ),
        SmartBetAnalysisSettlement.unsupported,
        reason: '$market must not be settled from FT score alone',
      );
    }
  });

  test('B78: first/second half scenario is sporting and explicitly uncalibrated',
      () {
    final estimates = service.halfTimeScenarios(sample());
    expect(estimates.length, 6);
    expect(estimates.every((e) => e.experimental), isTrue);
    expect(estimates.every((e) => e.probabilityPercent != null), isTrue);
    final p1 = estimates.take(3)
        .fold<double>(0, (sum, e) => sum + e.probabilityPercent!);
    final p2 = estimates.skip(3)
        .fold<double>(0, (sum, e) => sum + e.probabilityPercent!);
    expect(p1, closeTo(100, 0.0001));
    expect(p2, closeTo(100, 0.0001));
    expect(estimates[0].probabilityPercent!,
        greaterThan(estimates[2].probabilityPercent!));
    expect(estimates[3].probabilityPercent!,
        greaterThan(estimates[5].probabilityPercent!));
  });

  test('B78: invalid xG never becomes an invented half forecast', () {
    for (final value in [0.0, double.nan, double.infinity, -1.0]) {
      final forecasts = service.halfTimeScenarios(sample(home: value));
      expect(forecasts.every((e) => e.probabilityPercent == null), isTrue);
    }
  });

  test('B78: corner and shots need verified coverage before showing rates', () {
    final missing = service.countMarketEvidence(
      family: GoalVdLineExtraMarketFamily.totalCorners,
    );
    expect(missing.length, 12);
    expect(missing.every((e) => e.probabilityPercent == null), isTrue);
    final short = service.countMarketEvidence(
      family: GoalVdLineExtraMarketFamily.totalShotsOnTarget,
      sample: const GoalVdLineVerifiedCountSample(
        totals: [5, 6, 8], distinctMatchdays: 3,
      ),
    );
    expect(short.length, 12);
    expect(short.every((e) => e.probabilityPercent == null), isTrue);
    final qualified = service.countMarketEvidence(
      family: GoalVdLineExtraMarketFamily.totalCorners,
      sample: GoalVdLineVerifiedCountSample(
        totals: List<int>.filled(100, 9), distinctMatchdays: 16,
      ),
    );
    expect(qualified.first.probabilityPercent, 100);
    expect(qualified[1].probabilityPercent, 0);
    expect(qualified.every((e) => e.experimental), isTrue);
  });

  test('B78: half 1X2 settled with actual halftime and regulation FT', () {
    const verified = GoalVdLineVerifiedExtraOutcome(
      homeAtHalfTime: 1, awayAtHalfTime: 0,
      homeAtFullTime: 1, awayAtFullTime: 2,
    );
    expect(settlement.evaluate(market: '1T 1', verified: verified),
        GoalVdLineExtraSettlement.correct);
    expect(settlement.evaluate(market: '1T X', verified: verified),
        GoalVdLineExtraSettlement.wrong);
    expect(settlement.evaluate(market: '2T 2', verified: verified),
        GoalVdLineExtraSettlement.correct);
    expect(settlement.evaluate(market: '2T 1', verified: verified),
        GoalVdLineExtraSettlement.wrong);
  });

  test('B78: missing HT or impossible HT/FT must not be settled', () {
    const noHalf = GoalVdLineVerifiedExtraOutcome(
      homeAtFullTime: 2, awayAtFullTime: 1,
    );
    const impossible = GoalVdLineVerifiedExtraOutcome(
      homeAtHalfTime: 3, awayAtHalfTime: 0,
      homeAtFullTime: 2, awayAtFullTime: 2,
    );
    expect(settlement.evaluate(market: '1T X', verified: noHalf),
        GoalVdLineExtraSettlement.unsupported);
    expect(settlement.evaluate(market: '2T X', verified: impossible),
        GoalVdLineExtraSettlement.unsupported);
  });

  test('B78: corner and match shots settle only from actual count', () {
    const verified = GoalVdLineVerifiedExtraOutcome(
      homeAtFullTime: 2, awayAtFullTime: 1,
      totalCorners: 9, totalShotsOnTarget: 6,
    );
    expect(settlement.evaluate(market: 'CORNER OVER 8.5', verified: verified),
        GoalVdLineExtraSettlement.correct);
    expect(settlement.evaluate(market: 'CORNER UNDER 8.5', verified: verified),
        GoalVdLineExtraSettlement.wrong);
    expect(settlement.evaluate(market: 'TIRI PORTA OVER 6.5', verified: verified),
        GoalVdLineExtraSettlement.wrong);
    expect(settlement.evaluate(market: 'TIRI PORTA UNDER 6.5', verified: verified),
        GoalVdLineExtraSettlement.correct);
    expect(settlement.evaluate(
      market: 'TIRI PORTA UNDER 6.5',
      verified: const GoalVdLineVerifiedExtraOutcome(
        homeAtFullTime: 0, awayAtFullTime: 0,
      ),
    ), GoalVdLineExtraSettlement.unsupported);
  });

  test('B78: API-Football regular-time fixture and full stat rows', () {
    final payload = <String, dynamic>{
      'fixture': {'id': 100, 'status': {'short': 'AET'}},
      'score': {
        'halftime': {'home': 1, 'away': 0},
        'fulltime': {'home': 1, 'away': 1},
      },
      'goals': {'home': 3, 'away': 2},
    };
    final statistics = [
      {
        'team': {'id': 10},
        'statistics': [
          {'type': 'Corner Kicks', 'value': 4},
          {'type': 'Shots on Goal', 'value': 2},
        ],
      },
      {
        'team': {'id': 11},
        'statistics': [
          {'type': 'Corner Kicks', 'value': 5},
          {'type': 'Shots on Goal', 'value': 3},
        ],
      },
    ];
    final outcome = settlement.fromApiFixture(
      payload, teamStatistics: statistics,
    )!;
    expect(outcome.homeAtFullTime, 1);
    expect(outcome.awayAtFullTime, 1);
    expect(outcome.totalCorners, 9);
    expect(outcome.totalShotsOnTarget, 5);
    expect(settlement.evaluate(market: '2T 2', verified: outcome),
        GoalVdLineExtraSettlement.correct);
  });

  test('B78: awarded, ambiguous or absent provider stats fail closed', () {
    const stats = [
      {'team': {'id': 10}, 'statistics': [
        {'type': 'Corner Kicks', 'value': 5},
      ]},
      {'team': {'id': 10}, 'statistics': [
        {'type': 'Corner Kicks', 'value': 5},
      ]},
    ];
    final base = <String, dynamic>{
      'fixture': {'id': 200, 'status': {'short': 'FT'}},
      'goals': {'home': 2, 'away': 2},
      'score': {'halftime': {'home': 0, 'away': 0}},
    };
    expect(settlement.fromApiFixture({...base,
      'fixture': {'id': 200, 'status': {'short': 'AWD'}},
    }), isNull);
    final verified = settlement.fromApiFixture(
      base, teamStatistics: stats,
    )!;
    expect(verified.totalCorners, isNull);
    expect(verified.totalShotsOnTarget, isNull);
    expect(settlement.evaluate(
      market: 'CORNER OVER 8.5', verified: verified,
    ), GoalVdLineExtraSettlement.unsupported);
  });

  test('B78: odds parser maps only exact full-match bet groups', () {
    expect(GoalVdLineExtraMarketsOddsParser.outcomeFor(
      betName: '1st Half Winner', value: 'Home',
    ), '1T 1');
    expect(GoalVdLineExtraMarketsOddsParser.outcomeFor(
      betName: 'Second Half Result', value: 'Draw',
    ), '2T X');
    expect(GoalVdLineExtraMarketsOddsParser.outcomeFor(
      betName: 'Total Corners', value: 'Over 9.5',
    ), 'CORNER OVER 9.5');
    expect(GoalVdLineExtraMarketsOddsParser.outcomeFor(
      betName: 'Total Shots on Target', value: 'Under 6.5',
    ), 'TIRI PORTA UNDER 6.5');
  });

  test('B78: FT 1X2 and player substitute markets cannot leak', () {
    final parser = GoalVdLineExtraMarketsOddsParser.outcomeFor;
    expect(parser(betName: 'Match Winner', value: 'Home'), isNull);
    expect(parser(betName: '1st Half Handicap', value: 'Home'), isNull);
    expect(parser(betName: 'Player Shots on Target', value: 'Over 1.5'), isNull);
    expect(parser(betName: 'Shots on Target Substitute+',
      value: 'Over 1.5'), isNull);
    expect(parser(betName: 'Home Team Total Corners',
      value: 'Over 9.5'), isNull);
    expect(parser(betName: 'Total Corners', value: 'Over 25.5'), isNull);
    expect(parser(betName: 'Total Corners', value: 'Exactly 9'), isNull);
  });
}
