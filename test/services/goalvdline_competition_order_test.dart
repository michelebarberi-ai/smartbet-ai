import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_competition_order.dart';

void main() {
  test('B49: preview combinazioni mostra paese e campionato', () {
    expect(
      GoalVdLineCompetitionOrder.matchCompetitionLabel(
        'Italy', 'Serie C - Girone A',
      ),
      'ITALIA · Serie C - Girone A',
    );
    expect(
      GoalVdLineCompetitionOrder.matchCompetitionLabel(
        'Spain', 'Segunda División RFEF - Group 2',
      ),
      'SPAGNA · Segunda División RFEF - Group 2',
    );
    expect(
      GoalVdLineCompetitionOrder.matchCompetitionLabel(
        'Europe', 'AFC Champions League Elite',
      ),
      'ASIA · AFC Champions League Elite',
    );
    expect(
      GoalVdLineCompetitionOrder.matchCompetitionLabel('', ''),
      'Campionato non disponibile',
    );
    expect(
      GoalVdLineCompetitionOrder.matchCompetitionLabel('', 'Serie A'),
      'Serie A',
    );
  });

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

  test('P23B1A: AFC visualizzata in Asia anche se API dice Europa', () {
    expect(
      GoalVdLineCompetitionOrder.displayCountry(
        'Europa',
        'AFC Champions League Elite',
      ),
      'ASIA',
    );
    expect(
      GoalVdLineCompetitionOrder.displayCountry('Giappone', 'J1 League'),
      'GIAPPONE',
    );
    expect(
      GoalVdLineCompetitionOrder.displayCountry(
        'Europe',
        'UEFA Champions League',
      ),
      'EUROPA',
    );
  });

  test('P23B1A2: AGCFF e Gulf Champions League sono ASIA', () {
    expect(
      GoalVdLineCompetitionOrder.displayCountry(
        'Europa',
        'AGCFF Gulf Champions League',
      ),
      'ASIA',
    );
    expect(
      GoalVdLineCompetitionOrder.displayCountry(
        'Europe',
        'AGCFF Gulf Club Champions League',
      ),
      'ASIA',
    );
    expect(
      GoalVdLineCompetitionOrder.displayCountry(
        'Europa',
        'Gulf Club Champions League',
      ),
      'ASIA',
    );
    expect(
      GoalVdLineCompetitionOrder.displayCountry(
        'Europa',
        'AFC Champions League Elite',
      ),
      'ASIA',
    );
    expect(
      GoalVdLineCompetitionOrder.displayCountry(
        'Europa',
        'UEFA Champions League',
      ),
      'EUROPA',
    );
    expect(
      GoalVdLineCompetitionOrder.displayCountry('Europa', 'US Gulf Coast Cup'),
      'EUROPA',
    );
  });
}
