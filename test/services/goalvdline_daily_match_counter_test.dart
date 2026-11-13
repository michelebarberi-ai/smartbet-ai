import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/goalvdline_daily_match_counter.dart';

void main() {
  final now = DateTime(2026, 11, 13, 9);

  MatchModel fixture({
    required int id,
    DateTime? kickoff,
    String status = 'NS',
    String date = '',
    String league = 'Serie A',
    String country = 'Italia',
    int homeId = 100,
    int awayId = 200,
  }) => MatchModel(
    fixtureId: id,
    homeTeamId: homeId,
    awayTeamId: awayId,
    homeTeam: 'Home',
    awayTeam: 'Away',
    league: league,
    leagueId: 135,
    country: country,
    countryCode: 'IT',
    date: date.isEmpty
        ? (kickoff ?? DateTime(2026, 11, 13, 20)).toIso8601String()
        : date,
    statusShort: status,
    leagueType: 'domestic',
    isEuropeanCup: false,
    isFriendly: false,
    isNational: false,
    aiWeight: 0.8,
    smartScore: 0,
    homeWin: 0,
    draw: 0,
    awayWin: 0,
    valueBet: '',
    odd: 0,
  );

  test('B45 morning: counts only distinct upcoming fixtures today', () {
    final count = GoalVdLineDailyMatchCounter.countForToday([
      fixture(id: 1),
      fixture(id: 1),
      fixture(id: 2, kickoff: DateTime(2026, 11, 13, 21)),
      fixture(id: 3, kickoff: DateTime(2026, 11, 14, 10)),
      fixture(id: 4, kickoff: DateTime(2026, 11, 13, 8)),
      fixture(id: 5, status: 'FT'),
      fixture(id: 6, status: 'PST'),
      fixture(id: 7, homeId: 0),
      fixture(id: 8, league: 'Under 19 Youth League'),
      fixture(id: 9, date: 'bad-date'),
      fixture(id: 0),
    ], now: now);
    expect(count, 2);
  });

  test('B45 morning: empty and no eligible results are truly zero', () {
    expect(GoalVdLineDailyMatchCounter.countForToday([], now: now), 0);
    expect(GoalVdLineDailyMatchCounter.countForToday([
      fixture(id: 1, kickoff: DateTime(2026, 11, 14, 20)),
    ], now: now), 0);
  });

  test('B45 morning: an upcoming fixture is not an AI-confirmed forecast', () {
    // No scores or odds are required: this service only counts fixtures.
    final game = fixture(id: 1);
    expect(game.smartScore, 0);
    expect(GoalVdLineDailyMatchCounter.countForToday([game], now: now), 1);
  });
}
