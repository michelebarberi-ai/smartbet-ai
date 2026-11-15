import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_auto_fixture_selection_service.dart';

void main() {
  const selector = SmartBetAutoFixtureSelectionService();
  SmartBetAutomaticFixtureEstimate make(int id, double? p, [double? quality]) =>
      SmartBetAutomaticFixtureEstimate(
        fixtureId: id,
        probability: p,
        dataQuality: quality,
      );

  test('P21U: l utente richiede soltanto il numero, massimo 15', () {
    final pool = List.generate(40, (i) => make(i + 1, (i + 1) / 100, 0.7));
    final results = selector.shortlist(candidates: pool, requestedCount: 5);
    expect(results.length, 12);
    expect(results.first, 40);
    expect(results, contains(29));
  });

  test('P21U: ricerca 15 partite approfondisce al massimo 30', () {
    final pool = List.generate(45, (i) => make(i + 1, 0.2 + i / 100, 0.8));
    expect(selector.shortlist(candidates: pool, requestedCount: 15).length, 30);
  });

  test('P21U: non scarta fixture poco affidabili quando ne restano poche', () {
    final pool = [
      make(1, null),
      make(2, 0.25, 0.2),
      make(3, null),
      make(4, 0.4),
    ];
    expect(
      selector.shortlist(candidates: pool, requestedCount: 4),
      hasLength(4),
    );
  });

  test('P21U: nessun dato produce una lista vuota, non inventa fixture', () {
    expect(selector.shortlist(candidates: [], requestedCount: 4), isEmpty);
  });

  test('P21U: rifiuta richieste oltre 15 e duplicati', () {
    expect(
      () => selector.shortlist(candidates: [], requestedCount: 16),
      throwsArgumentError,
    );
    expect(
      () => selector.shortlist(
        candidates: [make(1, .3), make(1, .4)],
        requestedCount: 3,
      ),
      throwsArgumentError,
    );
  });

  test('P21U: quote non sono input nella preselezione', () {
    final pool = [make(1, .4, .8), make(2, .3, .8)];
    expect(selector.shortlist(candidates: pool, requestedCount: 3), [1, 2]);
  });

  test('B52: first 45 do not monopolize selection from a single league', () {
    final fixtures = <({int id, String league})>[
      for (var i = 0; i < 80; i++) (id: i + 1, league: 'Serie D'),
      (id: 81, league: 'Serie A'),
      (id: 82, league: 'Serie B'),
      (id: 83, league: 'Premier League'),
    ];
    final covered = selector.diversifiedPreliminary(
      candidates: fixtures,
      competitionKeyOf: (item) => item.league,
      limit: 6,
    );
    expect(covered.map((item) => item.id), [1, 81, 82, 83, 2, 3]);
  });

  test('B52: previews retain chronological order inside competitions', () {
    final fixtures = <({int id, String league})>[
      (id: 1, league: 'C'),
      (id: 2, league: 'C'),
      (id: 3, league: 'A'),
      (id: 4, league: 'B'),
      (id: 5, league: 'A'),
    ];
    final covered = selector.diversifiedPreliminary(
      candidates: fixtures,
      competitionKeyOf: (item) => item.league,
      limit: 5,
    );
    expect(covered.map((item) => item.id), [1, 3, 4, 2, 5]);
  });

  test('B52: preliminary search enforces its budget without fake results', () {
    final results = selector.diversifiedPreliminary(
      candidates: <int>[1, 2, 3],
      competitionKeyOf: (_) => 'A',
      limit: 2,
    );
    expect(results, [1, 2]);
    expect(() => selector.diversifiedPreliminary(
      candidates: <int>[],
      competitionKeyOf: (_) => 'A',
      limit: -1,
    ), throwsArgumentError);
  });

}
