import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/italy_schedule_filter.dart';

MatchModel fixture({
  String country = 'Italia',
  required String league,
}) {
  return MatchModel(
    fixtureId: 101,
    homeTeamId: 201,
    awayTeamId: 202,
    homeTeam: 'Casa',
    awayTeam: 'Ospite',
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
