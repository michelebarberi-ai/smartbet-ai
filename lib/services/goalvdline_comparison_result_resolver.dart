import 'football_api_service.dart';
import 'goalvdline_comparison_store.dart';

typedef GoalVdLineFixturesByDateFetcher =
    Future<List<dynamic>> Function(DateTime date);

class GoalVdLineResultResolutionSummary {
  final int unresolvedBefore;
  final int eligible;
  final int skippedNotDue;
  final int datesQueried;
  final int resolved;
  final int apiErrors;
  final int unresolvedAfter;

  const GoalVdLineResultResolutionSummary({
    required this.unresolvedBefore,
    required this.eligible,
    required this.skippedNotDue,
    required this.datesQueried,
    required this.resolved,
    required this.apiErrors,
    required this.unresolvedAfter,
  });
}

class GoalVdLineComparisonResultResolver {
  final GoalVdLineComparisonStore _store;

  final GoalVdLineFixturesByDateFetcher _fetchByDate;

  GoalVdLineComparisonResultResolver({
    GoalVdLineComparisonStore? store,
    GoalVdLineFixturesByDateFetcher? fetchByDate,
  }) : _store = store ?? GoalVdLineComparisonStore.instance,
       _fetchByDate = fetchByDate ?? FootballApiService().getMatchesByDate;

  // ============================================================
  // RISOLUZIONE RISULTATI
  // ============================================================
  //
  // Aspettiamo almeno 4 ore dal calcio d'inizio prima di
  // interrogare una fixture. Lo stato API resta comunque
  // l'autorità finale.
  //
  // Stati conclusi coerenti con i backtest GoalVdLine:
  // FT, AET, PEN, AWD, WO.
  // ============================================================

  Future<GoalVdLineResultResolutionSummary> resolvePending({
    DateTime? now,
  }) async {
    final currentTime = (now ?? DateTime.now()).toLocal();

    final allBefore = await _store.readAll();

    final unresolved = allBefore
        .where((record) => !record.hasActualResult)
        .toList();

    final eligible = <GoalVdLineComparisonRecord>[];

    var skippedNotDue = 0;

    for (final record in unresolved) {
      final kickoff = record.matchDate.toLocal();

      final age = currentTime.difference(kickoff);

      if (age < const Duration(hours: 4)) {
        skippedNotDue++;
        continue;
      }

      eligible.add(record);
    }

    final grouped = <String, List<GoalVdLineComparisonRecord>>{};

    for (final record in eligible) {
      final date = record.matchDate.toLocal();

      final key = _dateKey(date);

      (grouped[key] ??= <GoalVdLineComparisonRecord>[]).add(record);
    }

    final keys = grouped.keys.toList()..sort();

    var datesQueried = 0;
    var resolved = 0;
    var apiErrors = 0;

    for (final key in keys) {
      final records = grouped[key]!;

      if (records.isEmpty) {
        continue;
      }

      final firstDate = records.first.matchDate.toLocal();

      final queryDate = DateTime(
        firstDate.year,
        firstDate.month,
        firstDate.day,
      );

      List<dynamic> fixtures;

      try {
        fixtures = await _fetchByDate(queryDate);

        datesQueried++;
      } catch (_) {
        apiErrors++;
        continue;
      }

      final rawByFixture = <int, Map<String, dynamic>>{};

      for (final item in fixtures) {
        if (item is! Map) {
          continue;
        }

        final raw = Map<String, dynamic>.from(item);

        final fixture = raw['fixture'];

        if (fixture is! Map) {
          continue;
        }

        final fixtureMap = Map<String, dynamic>.from(fixture);

        final fixtureId = _toInt(fixtureMap['id']);

        if (fixtureId > 0) {
          rawByFixture[fixtureId] = raw;
        }
      }

      for (final record in records) {
        final raw = rawByFixture[record.fixtureId];

        if (raw == null) {
          continue;
        }

        final actual = _actualResult(raw);

        if (actual == null) {
          continue;
        }

        _store.registerActualResult(
          fixtureId: record.fixtureId,
          homeGoals: actual.homeGoals,
          awayGoals: actual.awayGoals,
        );

        resolved++;
      }
    }

    // readAll() aspetta la coda interna dello store:
    // garantisce che tutte le registerActualResult siano
    // state persistite prima di restituire il riepilogo.
    final allAfter = await _store.readAll();

    final unresolvedAfter = allAfter
        .where((record) => !record.hasActualResult)
        .length;

    return GoalVdLineResultResolutionSummary(
      unresolvedBefore: unresolved.length,
      eligible: eligible.length,
      skippedNotDue: skippedNotDue,
      datesQueried: datesQueried,
      resolved: resolved,
      apiErrors: apiErrors,
      unresolvedAfter: unresolvedAfter,
    );
  }

  // ============================================================
  // RISULTATO REALE
  // ============================================================

  _GoalVdLineActualResult? _actualResult(Map<String, dynamic> raw) {
    final fixtureRaw = raw['fixture'];
    final goalsRaw = raw['goals'];

    if (fixtureRaw is! Map || goalsRaw is! Map) {
      return null;
    }

    final fixture = Map<String, dynamic>.from(fixtureRaw);

    final goals = Map<String, dynamic>.from(goalsRaw);

    final statusRaw = fixture['status'];

    if (statusRaw is! Map) {
      return null;
    }

    final status = Map<String, dynamic>.from(statusRaw);

    final short = status['short']?.toString().toUpperCase() ?? '';

    const finished = <String>{'FT', 'AET', 'PEN', 'AWD', 'WO'};

    if (!finished.contains(short)) {
      return null;
    }

    final home = _nullableInt(goals['home']);
    final away = _nullableInt(goals['away']);

    if (home == null || away == null) {
      return null;
    }

    return _GoalVdLineActualResult(homeGoals: home, awayGoals: away);
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _nullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value.toString());
  }
}

class _GoalVdLineActualResult {
  final int homeGoals;
  final int awayGoals;

  const _GoalVdLineActualResult({
    required this.homeGoals,
    required this.awayGoals,
  });
}
