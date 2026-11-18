import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/goalvdline_coupon_screening_policy.dart';

MatchModel match({
  int fixture = 1,
  int leagueId = 39,
  String country = 'England',
  String league = 'Premier League',
  String home = 'Arsenal',
  String away = 'Chelsea',
  double weight = 0.80,
}) => MatchModel(
  fixtureId: fixture,
  homeTeamId: 10 + fixture,
  awayTeamId: 100 + fixture,
  homeTeam: home,
  awayTeam: away,
  league: league,
  leagueId: leagueId,
  country: country,
  countryCode: '',
  date: '2026-11-21T17:00:00Z',
  leagueType: 'domestic',
  isEuropeanCup: false,
  isFriendly: false,
  isNational: false,
  aiWeight: weight,
  smartScore: 0,
  homeWin: 0,
  draw: 0,
  awayWin: 0,
  valueBet: '',
  odd: 0,
);

AnalysisResult analysis({
  int score = 72,
  int confidence = 70,
  int home = 47,
  int draw = 24,
  int away = 29,
  int o15 = 77,
}) => AnalysisResult(
  smartScore: score,
  dataConfidence: confidence,
  homeProbability: home,
  drawProbability: draw,
  awayProbability: away,
  over15Probability: o15,
  under15Probability: 23,
  over25Probability: 55,
  under25Probability: 45,
  goalProbability: 59,
  noGoalProbability: 41,
  prediction: '1',
  valueBet: '',
  risk: 'Medio',
  expectedHomeGoals: 1.65,
  expectedAwayGoals: 1.10,
);

void main() {
  test('B70: Wednesday 18 Nov 2026 weekend is Sat 21 and Sun 22',
      () {
    final weekend = GoalVdLineCouponScreeningPolicy.nextWeekend(
      DateTime(2026, 11, 18, 19, 14));
    expect(weekend, [
      DateTime(2026, 11, 21),
      DateTime(2026, 11, 22),
    ]);
  });

  test('B70: Saturday includes current Sat and Sun; Sunday uses next pair',
      () {
    expect(GoalVdLineCouponScreeningPolicy.nextWeekend(
      DateTime(2026, 11, 21, 14)), [
      DateTime(2026, 11, 21),
      DateTime(2026, 11, 22),
    ]);
    expect(GoalVdLineCouponScreeningPolicy.nextWeekend(
      DateTime(2026, 11, 22, 14)), [
      DateTime(2026, 11, 28),
      DateTime(2026, 11, 29),
    ]);
  });

  test('B70: Italy schedule excludes U17, reserves, minor when enabled',
      () {
    final fixtures = [
      match(fixture: 1),
      match(fixture: 2, leagueId: 42,
          league: 'Premier League Cup', home: 'Man Utd U21',
          away: 'Aston Villa U21'),
      match(fixture: 3, leagueId: 40, country: 'Spain',
          league: 'La Liga', home: 'Getafe', away: 'Alaves'),
      match(fixture: 4, leagueId: 777, country: 'World',
          league: 'World Cup U17', home: 'Korea Republic U17',
          away: 'New Caledonia U17'),
      match(fixture: 5, leagueId: 78, country: 'Germany',
          league: 'Bundesliga', home: 'Bayern', away: 'Stuttgart'),
    ];
    expect(GoalVdLineCouponScreeningPolicy.eligibleMatches(fixtures,
        italianScheduleOnly: true).map((x) => x.fixtureId).toList(),
        [1, 3, 5]);
    expect(GoalVdLineCouponScreeningPolicy.eligibleMatches(fixtures,
        italianScheduleOnly: false).length, 5);
  });

  test('B70: OR 99% cannot inflate screening probability above common odds',
      () {
    final result = analysis();
    expect(GoalVdLineCouponScreeningPolicy.comparableMarketProbability(result),
        77);
    final p = GoalVdLineCouponScreeningPolicy.screeningScore(
      analysis: result, match: match());
    expect(p, greaterThan(0));
    expect(p, lessThan(100));
  });

  test('B70: stronger sport/coverage data wins before obscure fixture',
      () {
    final main = GoalVdLineCouponScreeningPolicy.screeningScore(
      analysis: analysis(score: 78, confidence: 80),
      match: match(weight: 0.85),
    );
    final thin = GoalVdLineCouponScreeningPolicy.screeningScore(
      analysis: analysis(score: 52, confidence: 20),
      match: match(weight: 0.40, league: 'Unknown Regional League'),
    );
    expect(main, greaterThan(thin));
  });

  test('B70: deep shortlist spreads across leagues and backfills to capacity',
      () {
    final ranked = [
      for (var i = 0; i < 12; i++)
        match(fixture: i + 1, leagueId: 39),
      for (var i = 12; i < 20; i++)
        match(fixture: i + 1, leagueId: 40,
              country: 'Spain', league: 'La Liga'),
      for (var i = 20; i < 26; i++)
        match(fixture: i + 1, leagueId: 78,
              country: 'Germany', league: 'Bundesliga'),
    ];
    List<MatchModel> select(int limit) =>
        GoalVdLineCouponScreeningPolicy.diversifiedTop(
          ranked,
          limit: limit,
          leagueIdOf: (item) => item.leagueId,
          leagueNameOf: (item) => item.league,
          countryOf: (item) => item.country,
        );
    final selected = select(12);
    expect(selected.length, 12);
    expect(selected.where((x) => x.leagueId == 39).length, 4);
    expect(selected.where((x) => x.leagueId == 40).length, 4);
    expect(selected.where((x) => x.leagueId == 78).length, 4);
    final backfilled = select(24);
    expect(backfilled.length, 24);
    expect(backfilled.map((x) => x.fixtureId).toSet().length, 24);
  });

  test('B70: no forced selections when candidates are insufficient', () {
    final one = [match()];
    final selected = GoalVdLineCouponScreeningPolicy.diversifiedTop(
      one,
      limit: 36,
      leagueIdOf: (item) => item.leagueId,
      leagueNameOf: (item) => item.league,
      countryOf: (item) => item.country,
    );
    expect(selected.length, 1);
  });
}
