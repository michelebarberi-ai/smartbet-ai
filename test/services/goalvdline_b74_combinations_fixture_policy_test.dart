import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/goalvdline_combinations_fixture_policy.dart';
import 'package:smartbet_ai_new/widgets/competition_filter_sheet.dart';

MatchModel fixture(
  int id, {
  required int leagueId,
  required String country,
  required String league,
  String home = 'Home',
  String away = 'Away',
  bool future = true,
}) => MatchModel(
  fixtureId: id,
  homeTeamId: 500 + id,
  awayTeamId: 900 + id,
  homeTeam: home,
  awayTeam: away,
  league: league,
  leagueId: leagueId,
  country: country,
  countryCode: '',
  date: future ? '2026-11-20T18:00:00Z' : '2026-11-17T18:00:00Z',
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

void main() {
  final all = [
    fixture(1, leagueId: 135, country: 'Italy', league: 'Serie A'),
    fixture(2, leagueId: 999, country: 'England',
        league: 'Premier League 2', home: 'Chelsea U21'),
    fixture(3, leagueId: 39, country: 'England', league: 'Premier League'),
    fixture(4, leagueId: 998, country: 'World', league: 'Regional Friendly'),
    fixture(5, leagueId: 40, country: 'Spain', league: 'La Liga'),
    fixture(6, leagueId: 777, country: 'Unknown', league: 'Unknown Regional'),
    fixture(7, leagueId: 78, country: 'Germany', league: 'Bundesliga',
        future: false),
  ];

  List<MatchModel> filter({
    bool italy = true,
    Set<String> selected = const {},
  }) => GoalVdLineCombinationsFixturePolicy.eligibleMatches(
        all,
        italianScheduleOnly: italy,
        selectedCompetitionKeys: selected,
        isUpcoming: (match) => match.fixtureId != 7,
      );

  test('B74: Italy schedule reduces fixtures BEFORE statistical analysis', () {
    expect(filter().map((m) => m.fixtureId).toList(), [1, 3, 5]);
    expect(filter(italy: false).map((m) => m.fixtureId).toList(),
        [1, 2, 3, 4, 5, 6]);
  });

  test('B74: selected league ID works together with Italy coverage', () {
    expect(filter(selected: {'id:39'}).map((m) => m.fixtureId).toList(), [3]);
    expect(filter(selected: {'id:999'}), isEmpty,
        reason: 'Youth leagues must not bypass Palinsesto Italia');
    expect(filter(italy: false, selected: {'id:999'})
        .map((m) => m.fixtureId).toList(), [2]);
  });

  test('B74: selection by country/league name remains supported', () {
    final key = CompetitionFilterSheet.keyFor(all[4]);
    expect(filter(selected: {key}).map((m) => m.fixtureId).toList(), [5]);
    expect(filter(selected: {'id:987654'}), isEmpty);
  });

  test('B74: catalog counts and analyzed fixture counts use same policy', () {
    final available = filter();
    final selected = GoalVdLineCombinationsFixturePolicy.eligibleMatches(
      available,
      italianScheduleOnly: true,
      selectedCompetitionKeys: {'id:135', 'id:40'},
      isUpcoming: (_) => true,
    );
    expect(available.length, 3);
    expect(selected.length, 2);
  });
}
