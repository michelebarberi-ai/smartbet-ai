import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/smartbet_scorer_learning_service.dart';

final _kickoff = DateTime.utc(2026, 11, 20, 19);
final _predicted = DateTime.utc(2026, 11, 19, 19);

SmartBetScorerLearningRecord _record({
  int fixtureId = 100,
  int playerId = 10,
  double probability = 0.65,
  DateTime? kickoffAt,
  DateTime? predictedAt,
}) => SmartBetScorerLearningRecord(
  fixtureId: fixtureId,
  playerId: playerId,
  playerName: 'Giocatore $playerId',
  kickoffAt: kickoffAt ?? _kickoff,
  predictedAt: predictedAt ?? _predicted,
  originalProbability: probability,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('salva sul dispositivo la stima originale', () async {
    final store = SmartBetScorerLearningStore();
    await store.capture([_record()]);
    final reloaded = SmartBetScorerLearningStore();
    await reloaded.initialize();
    expect(reloaded.records, hasLength(1));
    expect(reloaded.records.single.originalProbability, 0.65);
    expect(reloaded.records.single.isResolved, isFalse);
  });

  test('non sovrascrive la prima previsione con le successive', () async {
    final store = SmartBetScorerLearningStore();
    await store.capture([_record()]);
    await store.capture([_record(probability: 0.99)]);
    expect(store.records, hasLength(1));
    expect(store.records.single.originalProbability, 0.65);
  });

  test('rifiuta una previsione registrata dopo il kickoff', () async {
    final store = SmartBetScorerLearningStore();
    await store.capture([
      _record(predictedAt: _kickoff.add(const Duration(minutes: 3))),
    ]);
    expect(store.records, isEmpty);
  });

  test('riconosce i marcatori normali e su rigore', () {
    final result = SmartBetScorerGoalEventVerifier.verifiedGoals(
      homeGoals: 2,
      awayGoals: 0,
      events: [
        {
          'type': 'Goal',
          'detail': 'Normal Goal',
          'player': {'id': 10},
        },
        {
          'type': 'Goal',
          'detail': 'Penalty',
          'player': {'id': 10},
        },
      ],
    );
    expect(result, {10: 2});
  });

  test('un autogol conta per il risultato, non per il marcatore', () {
    final result = SmartBetScorerGoalEventVerifier.verifiedGoals(
      homeGoals: 1,
      awayGoals: 0,
      events: [
        {
          'type': 'Goal',
          'detail': 'Own Goal',
          'player': {'id': 10},
        },
      ],
    );
    expect(result, isEmpty);
  });

  test('eventi mancanti o incoerenti non vengono risolti', () {
    expect(
      SmartBetScorerGoalEventVerifier.verifiedGoals(
        homeGoals: 2,
        awayGoals: 0,
        events: [
          {
            'type': 'Goal',
            'detail': 'Normal Goal',
            'player': {'id': 10},
          },
        ],
      ),
      isNull,
    );
    expect(
      SmartBetScorerGoalEventVerifier.verifiedGoals(
        homeGoals: 1,
        awayGoals: 0,
        events: [
          {'type': 'Goal', 'detail': 'Normal Goal', 'player': {}},
        ],
      ),
      isNull,
    );
    expect(
      SmartBetScorerGoalEventVerifier.verifiedGoals(
        homeGoals: 1,
        awayGoals: 0,
        events: [
          {
            'type': 'Goal',
            'detail': 'Missed Penalty',
            'player': {'id': 10},
          },
        ],
      ),
      isNull,
    );
  });

  test('tre gare senza eventi non bloccano la quarta al riavvio', () async {
    final store = SmartBetScorerLearningStore();
    final ids = [101, 102, 103, 104];
    await store.capture([for (final id in ids) _record(fixtureId: id)]);
    final attempts = <int>[];
    SmartBetScorerResultResolver resolver(SmartBetScorerLearningStore storage) =>
        SmartBetScorerResultResolver(
          store: storage,
          fetchFixtures: (_) async => [
            for (final id in ids)
              {
                'fixture': {'id': id, 'status': {'short': 'FT'}},
                'goals': {'home': 1, 'away': 0},
              },
          ],
          fetchEvents: (id) async {
            attempts.add(id);
            if (id != 104) return [];
            return [
              {'type': 'Goal', 'detail': 'Missed Penalty'},
              {'type': 'Goal', 'detail': 'Normal Goal', 'player': {'id': 10}},
            ];
          },
        );
    final now = _kickoff.add(const Duration(hours: 6));
    expect(await resolver(store).resolvePending(now: now), 0);
    expect(attempts, [101, 102, 103]);
    attempts.clear();
    final reloaded = SmartBetScorerLearningStore();
    expect(await resolver(reloaded).resolvePending(now: now), 1);
    expect(attempts, [104, 101, 102]);
    expect(reloaded.records.singleWhere((r) => r.fixtureId == 104).actualGoals, 1);
  });

  test('risolve una fixture solo se FT e feed gol coerente', () async {
    final store = SmartBetScorerLearningStore();
    await store.capture([_record(playerId: 10), _record(playerId: 11)]);
    var fixturesFetched = 0;
    var eventsFetched = 0;
    final resolver = SmartBetScorerResultResolver(
      store: store,
      fetchFixtures: (day) async {
        fixturesFetched++;
        return [
          {
            'fixture': {
              'id': 100,
              'status': {'short': 'FT'},
            },
            'goals': {'home': 1, 'away': 0},
          },
        ];
      },
      fetchEvents: (fixtureId) async {
        eventsFetched++;
        return [
          {
            'type': 'Goal',
            'detail': 'Normal Goal',
            'player': {'id': 10},
          },
        ];
      },
    );
    expect(
      await resolver.resolvePending(
        now: _kickoff.add(const Duration(hours: 6)),
      ),
      1,
    );
    expect(fixturesFetched, 1);
    expect(eventsFetched, 1);
    expect(store.records.singleWhere((r) => r.playerId == 10).actualGoals, 1);
    expect(store.records.singleWhere((r) => r.playerId == 11).actualGoals, 0);
    expect(
      await resolver.resolvePending(
        now: _kickoff.add(const Duration(hours: 7)),
      ),
      0,
    );
    expect(eventsFetched, 1);
  });

  test('match AET non entra nello storico marcatori FT', () async {
    final store = SmartBetScorerLearningStore();
    await store.capture([_record()]);
    var eventsFetched = 0;
    final resolver = SmartBetScorerResultResolver(
      store: store,
      fetchFixtures: (_) async => [
        {
          'fixture': {
            'id': 100,
            'status': {'short': 'AET'},
          },
          'goals': {'home': 1, 'away': 0},
        },
      ],
      fetchEvents: (_) async {
        eventsFetched++;
        return [];
      },
    );
    expect(
      await resolver.resolvePending(
        now: _kickoff.add(const Duration(hours: 6)),
      ),
      0,
    );
    expect(eventsFetched, 0);
    expect(store.records.single.isResolved, isFalse);
  });

  test('nessuna chiamata rete prima delle quattro ore', () async {
    final store = SmartBetScorerLearningStore();
    await store.capture([_record()]);
    final resolver = SmartBetScorerResultResolver(
      store: store,
      fetchFixtures: (_) async => throw StateError('Non dovrebbe chiamare'),
      fetchEvents: (_) async => throw StateError('Non dovrebbe chiamare'),
    );
    expect(
      await resolver.resolvePending(
        now: _kickoff.add(const Duration(hours: 2)),
      ),
      0,
    );
  });

  test('calibrazione OFF e senza storico: nessuna modifica', () {
    final off = SmartBetScorerCalibrationService.evaluate(
      records: [],
      startedAt: DateTime.utc(2026, 12, 1),
      currentFixtureId: 999,
      originalProbability: 0.80,
      optedIn: false,
    );
    final on = SmartBetScorerCalibrationService.evaluate(
      records: [],
      startedAt: DateTime.utc(2026, 12, 1),
      currentFixtureId: 999,
      originalProbability: 0.80,
      optedIn: true,
    );
    expect(off.applied, isFalse);
    expect(on.applied, isFalse);
    expect(on.probability, 0.80);
  });

  test('gate validato: migliora Brier su partite distinte', () {
    final records = <SmartBetScorerLearningRecord>[];
    final first = DateTime.utc(2026, 5, 1);
    for (var i = 0; i < 120; i++) {
      final kickoff = first.add(Duration(days: i));
      final sample = _record(
        fixtureId: 1000 + i,
        playerId: 12,
        probability: 0.80,
        kickoffAt: kickoff,
        predictedAt: kickoff.subtract(const Duration(hours: 8)),
      );
      records.add(
        sample.withResult(
          goals: i.isEven ? 1 : 0,
          at: kickoff.add(const Duration(hours: 6)),
        ),
      );
    }
    final result = SmartBetScorerCalibrationService.evaluate(
      records: records,
      startedAt: DateTime.utc(2026, 11, 2),
      currentFixtureId: 999,
      originalProbability: 0.80,
      optedIn: true,
    );
    expect(result.applied, isTrue);
    expect(result.validatedFixtures, 36);
    expect(result.probability, lessThan(0.80));
    expect(result.probability, greaterThanOrEqualTo(0.70));
  });

  test('niente autofeedback dalla stessa fixture', () {
    final sample = _record().withResult(
      goals: 0,
      at: _kickoff.add(const Duration(hours: 6)),
    );
    final result = SmartBetScorerCalibrationService.evaluate(
      records: [sample],
      startedAt: _kickoff.add(const Duration(days: 3)),
      currentFixtureId: 100,
      originalProbability: 0.80,
      optedIn: true,
    );
    expect(result.applied, isFalse);
  });
}
