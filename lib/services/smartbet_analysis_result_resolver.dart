import 'football_api_service.dart';
import 'smartbet_analysis_history_store.dart';

typedef SmartBetAnalysisFixturesByDateFetcher =
    Future<List<dynamic>> Function(DateTime date);

class SmartBetAnalysisResultResolutionSummary {
  final int pendingRecordsBefore;
  final int pendingFixturesBefore;

  final int eligibleFixtures;
  final int skippedNotDue;

  final int datesQueried;
  final int resolvedFixtures;
  final int updatedRecords;

  final int apiErrors;

  final int pendingRecordsAfter;
  final int pendingFixturesAfter;

  const SmartBetAnalysisResultResolutionSummary({
    required this.pendingRecordsBefore,
    required this.pendingFixturesBefore,
    required this.eligibleFixtures,
    required this.skippedNotDue,
    required this.datesQueried,
    required this.resolvedFixtures,
    required this.updatedRecords,
    required this.apiErrors,
    required this.pendingRecordsAfter,
    required this.pendingFixturesAfter,
  });
}

class SmartBetAnalysisResultResolver {
  final SmartBetAnalysisHistoryStore _store;

  final SmartBetAnalysisFixturesByDateFetcher _fetchByDate;

  SmartBetAnalysisResultResolver({
    SmartBetAnalysisHistoryStore? store,
    SmartBetAnalysisFixturesByDateFetcher? fetchByDate,
  }) : _store = store ?? SmartBetAnalysisHistoryStore.instance,
       _fetchByDate = fetchByDate ?? FootballApiService().getMatchesByDate;

  // ============================================================
  // RISOLUZIONE
  // ============================================================
  //
  // - lavoriamo solo sui record ancora PENDING;
  // - deduplichiamo per fixture;
  // - aspettiamo almeno 4 ore dal kickoff;
  // - una singola risposta finale aggiorna TUTTI i mercati
  //   SmartBet/Diego associati alla stessa fixture;
  // - nessuna chiamata AI.
  // ============================================================

  Future<SmartBetAnalysisResultResolutionSummary> resolvePending({
    DateTime? now,
  }) async {
    await _store.initialize();

    final currentTime = (now ?? DateTime.now()).toLocal();

    final pendingBefore = _pendingRecords();

    final fixturesBefore = _fixtureIds(pendingBefore);

    // Una sola rappresentazione per fixture.
    final fixtureRecords = <int, SmartBetAnalysisRecord>{};

    for (final record in pendingBefore) {
      fixtureRecords.putIfAbsent(record.fixtureId, () => record);
    }

    final eligible = <int, SmartBetAnalysisRecord>{};

    var skippedNotDue = 0;

    for (final entry in fixtureRecords.entries) {
      final kickoff = entry.value.matchDate.toLocal();

      final age = currentTime.difference(kickoff);

      if (age < const Duration(hours: 4)) {
        skippedNotDue++;
        continue;
      }

      eligible[entry.key] = entry.value;
    }

    // ============================================================
    // RAGGRUPPAMENTO PER DATA
    //
    // FootballApiService recupera le fixture per giornata.
    // ============================================================

    final grouped = <String, List<SmartBetAnalysisRecord>>{};

    for (final record in eligible.values) {
      final date = record.matchDate.toLocal();

      final key = _dateKey(date);

      (grouped[key] ??= <SmartBetAnalysisRecord>[]).add(record);
    }

    final dateKeys = grouped.keys.toList()..sort();

    var datesQueried = 0;
    var resolvedFixtures = 0;
    var updatedRecords = 0;
    var apiErrors = 0;

    for (final dateKey in dateKeys) {
      final records = grouped[dateKey]!;

      if (records.isEmpty) {
        continue;
      }

      final localDate = records.first.matchDate.toLocal();

      final queryDate = DateTime(
        localDate.year,
        localDate.month,
        localDate.day,
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

        final fixtureRaw = raw['fixture'];

        if (fixtureRaw is! Map) {
          continue;
        }

        final fixture = Map<String, dynamic>.from(fixtureRaw);

        final fixtureId = _toInt(fixture['id']);

        if (fixtureId > 0) {
          rawByFixture[fixtureId] = raw;
        }
      }

      for (final record in records) {
        final raw = rawByFixture[record.fixtureId];

        if (raw == null) {
          continue;
        }

        final actual = _settlementResult(raw);

        if (actual == null) {
          continue;
        }

        final updated = await _store.registerActualResult(
          fixtureId: record.fixtureId,
          homeGoals: actual.homeGoals,
          awayGoals: actual.awayGoals,
        );

        if (updated <= 0) {
          continue;
        }

        resolvedFixtures++;
        updatedRecords += updated;
      }
    }

    final pendingAfter = _pendingRecords();

    return SmartBetAnalysisResultResolutionSummary(
      pendingRecordsBefore: pendingBefore.length,
      pendingFixturesBefore: fixturesBefore.length,
      eligibleFixtures: eligible.length,
      skippedNotDue: skippedNotDue,
      datesQueried: datesQueried,
      resolvedFixtures: resolvedFixtures,
      updatedRecords: updatedRecords,
      apiErrors: apiErrors,
      pendingRecordsAfter: pendingAfter.length,
      pendingFixturesAfter: _fixtureIds(pendingAfter).length,
    );
  }

  // ============================================================
  // RISULTATO UTILIZZABILE PER IL SETTLEMENT
  // ============================================================
  //
  // FT / AWD / WO:
  //   usiamo il risultato finale della fixture.
  //
  // AET / PEN:
  //   i mercati standard SmartBet/Diego sono mercati sul tempo
  //   regolamentare; quindi preferiamo score.fulltime.
  //
  //   Se quel dato manca, NON indoviniamo: il record resta pending.
  // ============================================================

  _SmartBetActualResult? _settlementResult(Map<String, dynamic> raw) {
    final fixtureRaw = raw['fixture'];

    if (fixtureRaw is! Map) {
      return null;
    }

    final fixture = Map<String, dynamic>.from(fixtureRaw);

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

    if (short == 'AET' || short == 'PEN') {
      final scoreRaw = raw['score'];

      if (scoreRaw is! Map) {
        return null;
      }

      final score = Map<String, dynamic>.from(scoreRaw);

      final fulltimeRaw = score['fulltime'];

      if (fulltimeRaw is! Map) {
        return null;
      }

      final fulltime = Map<String, dynamic>.from(fulltimeRaw);

      final home = _nullableInt(fulltime['home']);

      final away = _nullableInt(fulltime['away']);

      if (home == null || away == null) {
        return null;
      }

      return _SmartBetActualResult(homeGoals: home, awayGoals: away);
    }

    final goalsRaw = raw['goals'];

    if (goalsRaw is! Map) {
      return null;
    }

    final goals = Map<String, dynamic>.from(goalsRaw);

    final home = _nullableInt(goals['home']);

    final away = _nullableInt(goals['away']);

    if (home == null || away == null) {
      return null;
    }

    return _SmartBetActualResult(homeGoals: home, awayGoals: away);
  }

  List<SmartBetAnalysisRecord> _pendingRecords() {
    return _store.records
        .where((record) => record.status == SmartBetAnalysisStatus.pending)
        .toList(growable: false);
  }

  Set<int> _fixtureIds(List<SmartBetAnalysisRecord> records) {
    return records.map((record) => record.fixtureId).toSet();
  }

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

class _SmartBetActualResult {
  final int homeGoals;
  final int awayGoals;

  const _SmartBetActualResult({
    required this.homeGoals,
    required this.awayGoals,
  });
}
