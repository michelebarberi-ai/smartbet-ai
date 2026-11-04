import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_competition_order.dart';

void main() {
  test('P22: ordine paesi prioritari e alias italiani/inglesi', () {
    final values = [
      'Sweden',
      'Germany',
      'Italia',
      'England',
      'Europe',
      'Japan',
    ];
    values.sort(GoalVdLineCompetitionOrder.compareCountries);
    expect(values, [
      'Europe',
      'Italia',
      'England',
      'Germany',
      'Japan',
      'Sweden',
    ]);
    expect(GoalVdLineCompetitionOrder.country('Italy'), 'ITALIA');
    expect(GoalVdLineCompetitionOrder.country('Netherlands'), 'OLANDA');
    expect(GoalVdLineCompetitionOrder.country('Paesi Bassi'), 'OLANDA');
  });

  test('P22: date ordinarie, invalide alla fine', () {
    expect(
      GoalVdLineCompetitionOrder.compareTimes(
        '2026-11-04T16:00:00Z',
        '2026-11-04T20:00:00Z',
      ),
      lessThan(0),
    );
    expect(
      GoalVdLineCompetitionOrder.compareTimes('', '2026-11-04T20:00:00Z'),
      greaterThan(0),
    );
    expect(GoalVdLineCompetitionOrder.compareTimes(null, null), 0);
  });

  test('P22: nessuna competizione smarrita', () {
    expect(GoalVdLineCompetitionOrder.league(''), 'ALTRA COMPETIZIONE');
    expect(GoalVdLineCompetitionOrder.country(''), 'ALTRI');
    expect(GoalVdLineCompetitionOrder.country('Ecuador'), 'ECUADOR');
  });
}
