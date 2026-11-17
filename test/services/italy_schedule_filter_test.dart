import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/italy_schedule_filter.dart';

MatchModel fixture({
  String country = 'Italia',
  required String league,
  String homeTeam = 'Casa',
  String awayTeam = 'Ospite',
}) {
  return MatchModel(
    fixtureId: 101,
    homeTeamId: 201,
    awayTeamId: 202,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    league: league,
    leagueId: 0,
    country: country,
    countryCode: 'IT',
    date: '2026-11-15T14:30:00Z',
    leagueType: 'domestic',
    isEuropeanCup: false,
    isFriendly: false,
    isNational: false,
    aiWeight: 0.70,
    smartScore: 70,
    homeWin: 38,
    draw: 31,
    awayWin: 31,
    valueBet: '',
    odd: 1.30,
  );
}

void main() {
  test('B63: Premier League Cup e PL2 sono competizioni U21, non senior', () {
    for (final league in [
      'Premier League Cup',
      'Premier League Cup - Group B',
      'Premier League International Cup',
      'Premier League 2',
      'Professional Development League',
      'FA Youth Cup',
    ]) {
      expect(ItalyScheduleFilter.allows(
          fixture(country: 'Inghilterra', league: league)),
          isFalse, reason: league);
    }
    expect(ItalyScheduleFilter.allows(
        fixture(country: 'Inghilterra', league: 'Premier League')),
        isTrue);
    expect(ItalyScheduleFilter.allows(
        fixture(country: 'Inghilterra', league: 'FA Cup')),
        isTrue);
  });

  test('B63: nomi squadre U21 non diventano partite senior', () {
    expect(ItalyScheduleFilter.allows(fixture(
      country: 'Inghilterra',
      league: 'Premier League',
      homeTeam: 'Swansea City U21',
      awayTeam: 'Gillingham FC U21',
    )), isFalse);
    expect(ItalyScheduleFilter.allows(fixture(
      country: 'Internazionale',
      league: 'Nations League',
      homeTeam: 'Denmark',
      awayTeam: 'Norway',
    )), isTrue);
  });

  test('B65: Lowland League scozzese esclusa dal filtro Italia', () {
    expect(ItalyScheduleFilter.allows(fixture(
      country: 'Scotland',
      league: 'Football League - Lowland League',
      homeTeam: 'Berwick Rangers',
      awayTeam: 'Civil Service Strollers',
    )), isFalse);
    expect(ItalyScheduleFilter.allows(fixture(
      country: 'Internazionale',
      league: 'Africa Cup of Nations - Qualification',
      homeTeam: 'Liberia',
      awayTeam: 'Cape Verde Islands',
    )), isFalse);
  });

  test('B50: Palinsesto Italia ammette Serie D e tutti i gironi', () {
    for (final league in [
      'Serie D',
      'Serie D - Girone A',
      'Serie D - Girone B',
      'Serie D - Girone I',
      'SERIE D GROUP C',
    ]) {
      expect(ItalyScheduleFilter.allows(fixture(league: league)),
          isTrue, reason: league);
      expect(ItalyScheduleFilter.allows(
          fixture(country: 'Italy', league: league)),
          isTrue, reason: 'Italy / $league');
    }
  });

  test('B50: giovanili e amichevoli non diventano ammesse', () {
    expect(ItalyScheduleFilter.allows(
        fixture(league: 'Serie D U19')), isFalse);
    expect(ItalyScheduleFilter.allows(
        fixture(league: 'Serie D - Youth')), isFalse);
    expect(ItalyScheduleFilter.allows(
        fixture(league: 'Serie D Friendly')), isFalse);
  });

  test('B50: non confondere Serie D italiana con altre nazioni', () {
    expect(ItalyScheduleFilter.allows(
        fixture(country: 'Brazil', league: 'Serie D')), isFalse);
  });

  test('B50: esistenti Serie A/B/C e coppe restano disponibili', () {
    for (final league in [
      'Serie A', 'Serie B', 'Serie C - Girone A', 'Coppa Italia',
    ]) {
      expect(ItalyScheduleFilter.allows(fixture(league: league)),
          isTrue, reason: league);
    }
  });
}
