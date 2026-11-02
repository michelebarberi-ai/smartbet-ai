import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'football_api_service.dart';
import 'live_match_service.dart';

/// Una previsione per coppia partita/giocatore. Non viene mai riscritta
/// con una probabilita' calibrata: il modello apprende sulla sua stima pura.
class SmartBetScorerLearningRecord {
  final int fixtureId;
  final int playerId;
  final String playerName;
  final DateTime kickoffAt;
  final DateTime predictedAt;
  final double originalProbability;
  final int? actualGoals;
  final DateTime? resolvedAt;

  const SmartBetScorerLearningRecord({
    required this.fixtureId,
    required this.playerId,
    required this.playerName,
    required this.kickoffAt,
    required this.predictedAt,
    required this.originalProbability,
    this.actualGoals,
    this.resolvedAt,
  });

  String get key => '$fixtureId|$playerId';
  bool get isResolved => actualGoals != null && resolvedAt != null;
  bool get scored => (actualGoals ?? 0) >= 1;

  SmartBetScorerLearningRecord withResult({
    required int goals,
    required DateTime at,
  }) => SmartBetScorerLearningRecord(
    fixtureId: fixtureId,
    playerId: playerId,
    playerName: playerName,
    kickoffAt: kickoffAt,
    predictedAt: predictedAt,
    originalProbability: originalProbability,
    actualGoals: goals,
    resolvedAt: at.toUtc(),
  );

  Map<String, dynamic> toJson() => {
    'fixtureId': fixtureId,
    'playerId': playerId,
    'playerName': playerName,
    'kickoffAt': kickoffAt.toUtc().toIso8601String(),
    'predictedAt': predictedAt.toUtc().toIso8601String(),
    'originalProbability': originalProbability,
    'actualGoals': actualGoals,
    'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
  };

  factory SmartBetScorerLearningRecord.fromJson(Map<String, dynamic> data) {
    final record = SmartBetScorerLearningRecord(
      fixtureId: (data['fixtureId'] as num).toInt(),
      playerId: (data['playerId'] as num).toInt(),
      playerName: (data['playerName'] as String).trim(),
      kickoffAt: DateTime.parse(data['kickoffAt'] as String).toUtc(),
      predictedAt: DateTime.parse(data['predictedAt'] as String).toUtc(),
      originalProbability: (data['originalProbability'] as num).toDouble(),
      actualGoals: (data['actualGoals'] as num?)?.toInt(),
      resolvedAt: data['resolvedAt'] == null
          ? null
          : DateTime.parse(data['resolvedAt'] as String).toUtc(),
    );
    if (record.fixtureId <= 0 ||
        record.playerId <= 0 ||
        record.playerName.isEmpty ||
        record.originalProbability < 0 ||
        record.originalProbability > 1 ||
        !record.originalProbability.isFinite ||
        !record.predictedAt.isBefore(record.kickoffAt) ||
        (record.actualGoals != null && record.actualGoals! < 0) ||
        ((record.actualGoals == null) != (record.resolvedAt == null)) ||
        (record.resolvedAt != null &&
            !record.resolvedAt!.isAfter(record.kickoffAt))) {
      throw const FormatException('Scorer learning record non valido');
    }
    return record;
  }
}

/// Persistenza locale isolata: nuova chiave, nessuna migrazione o modifica
/// degli archivi precedenti delle previsioni SmartBet.
class SmartBetScorerLearningStore {
  static const storageKey = 'smartbet_scorer_learning_history_v1';

  final Future<SharedPreferences> Function()? preferencesLoader;
  List<SmartBetScorerLearningRecord> _records = [];
  bool _ready = false;

  SmartBetScorerLearningStore({this.preferencesLoader});

  Future<SharedPreferences> _preferences() =>
      (preferencesLoader ?? SharedPreferences.getInstance)();

  List<SmartBetScorerLearningRecord> get records =>
      List<SmartBetScorerLearningRecord>.unmodifiable(_records);

  Future<void> initialize() async {
    if (_ready) {
      return;
    }
    final prefs = await _preferences();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      _ready = true;
      return;
    }
    // Un archivio non leggibile non deve essere azzerato e sovrascritto.
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Archivio marcatori corrotto');
    }
    final loaded = <SmartBetScorerLearningRecord>[];
    for (final item in decoded) {
      if (item is! Map) {
        throw const FormatException('Archivio marcatori non valido');
      }
      loaded.add(
        SmartBetScorerLearningRecord.fromJson(Map<String, dynamic>.from(item)),
      );
    }
    _records = loaded;
    _ready = true;
  }

  Future<void> capture(List<SmartBetScorerLearningRecord> candidates) async {
    await initialize();
    final keys = _records.map((r) => r.key).toSet();
    var changed = false;
    for (final record in candidates) {
      if (record.fixtureId <= 0 ||
          record.playerId <= 0 ||
          record.playerName.trim().isEmpty ||
          !record.originalProbability.isFinite ||
          record.originalProbability < 0 ||
          record.originalProbability > 1 ||
          !record.predictedAt.toUtc().isBefore(record.kickoffAt.toUtc()) ||
          record.actualGoals != null ||
          record.resolvedAt != null ||
          !keys.add(record.key)) {
        continue;
      }
      _records.add(record);
      changed = true;
    }
    if (!changed) {
      return;
    }
    // Limite di dimensione, salvando prioritariamente i non risolti.
    if (_records.length > 4000) {
      final pending = _records.where((r) => !r.isResolved).toList();
      final resolved = _records.where((r) => r.isResolved).toList()
        ..sort((a, b) => b.predictedAt.compareTo(a.predictedAt));
      _records = [
        ...pending.take(4000),
        ...resolved.take(math.max(0, 4000 - pending.length)),
      ];
    }
    await _save();
  }

  Future<int> settleFixture({
    required int fixtureId,
    required Map<int, int> goalsByPlayer,
    required DateTime resolvedAt,
  }) async {
    await initialize();
    if (fixtureId <= 0) {
      return 0;
    }
    var updated = 0;
    final next = <SmartBetScorerLearningRecord>[];
    for (final item in _records) {
      if (item.fixtureId == fixtureId &&
          !item.isResolved &&
          resolvedAt.toUtc().isAfter(item.kickoffAt.toUtc())) {
        next.add(
          item.withResult(
            goals: goalsByPlayer[item.playerId] ?? 0,
            at: resolvedAt,
          ),
        );
        updated++;
      } else {
        next.add(item);
      }
    }
    if (updated > 0) {
      _records = next;
      await _save();
    }
    return updated;
  }

  Future<void> _save() async {
    final prefs = await _preferences();
    if (!await prefs.setString(
      storageKey,
      jsonEncode(_records.map((r) => r.toJson()).toList()),
    )) {
      throw StateError('Non e stato possibile salvare lo storico marcatori');
    }
  }
}

/// Verifica gli eventi dei gol senza confonderli con un gol della squadra.
/// Restituisce null se il feed e' assente, incompleto o contraddittorio.
class SmartBetScorerGoalEventVerifier {
  const SmartBetScorerGoalEventVerifier._();

  static Map<int, int>? verifiedGoals({
    required List<dynamic> events,
    required int homeGoals,
    required int awayGoals,
  }) {
    if (homeGoals < 0 || awayGoals < 0) {
      return null;
    }
    final credited = <int, int>{};
    var observedGoals = 0;
    for (final raw in events) {
      if (raw is! Map) {
        return null;
      }
      if (raw['type']?.toString().toLowerCase() != 'goal') {
        continue;
      }
      final detail = raw['detail']?.toString().trim().toLowerCase() ?? '';
      if (detail != 'normal goal' &&
          detail != 'penalty' &&
          detail != 'own goal') {
        // Non possiamo sapere se il provider considera valido l'evento.
        return null;
      }
      observedGoals++;
      if (detail == 'own goal') {
        continue;
      }
      final player = raw['player'];
      if (player is! Map) {
        return null;
      }
      final id = _toInt(player['id']);
      if (id <= 0) {
        return null;
      }
      credited[id] = (credited[id] ?? 0) + 1;
    }
    if (observedGoals != homeGoals + awayGoals) {
      return null;
    }
    return credited;
  }

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Nessuna chiamata AI. Massimo tre fixture risolte per apertura della pagina.
class SmartBetScorerResultResolver {
  final SmartBetScorerLearningStore store;
  final Future<List<dynamic>> Function(DateTime date) fetchFixtures;
  final Future<List<dynamic>> Function(int fixtureId) fetchEvents;

  SmartBetScorerResultResolver({
    required this.store,
    Future<List<dynamic>> Function(DateTime date)? fetchFixtures,
    Future<List<dynamic>> Function(int fixtureId)? fetchEvents,
  }) : fetchFixtures = fetchFixtures ?? FootballApiService().getMatchesByDate,
       fetchEvents = fetchEvents ?? LiveMatchService().getFixtureEvents;

  Future<int> resolvePending({DateTime? now, int maximumFixtures = 3}) async {
    await store.initialize();
    if (maximumFixtures <= 0) {
      return 0;
    }
    final at = (now ?? DateTime.now()).toUtc();
    final due = <int, SmartBetScorerLearningRecord>{};
    for (final r in store.records) {
      if (r.isResolved ||
          !at.isAfter(r.kickoffAt.add(const Duration(hours: 4)))) {
        continue;
      }
      due.putIfAbsent(r.fixtureId, () => r);
      if (due.length >= maximumFixtures) {
        break;
      }
    }
    if (due.isEmpty) {
      return 0;
    }

    final byDate = <String, List<SmartBetScorerLearningRecord>>{};
    for (final item in due.values) {
      final local = item.kickoffAt.toLocal();
      final key = '${local.year}-${local.month}-${local.day}';
      (byDate[key] ??= []).add(item);
    }
    var settled = 0;
    for (final entries in byDate.values) {
      final local = entries.first.kickoffAt.toLocal();
      List<dynamic> fixtures;
      try {
        fixtures = await fetchFixtures(
          DateTime(local.year, local.month, local.day),
        );
      } catch (_) {
        continue;
      }
      final fixtureById = <int, Map>{};
      for (final raw in fixtures) {
        if (raw is! Map || raw['fixture'] is! Map) {
          continue;
        }
        final id = SmartBetScorerGoalEventVerifier._toInt(
          (raw['fixture'] as Map)['id'],
        );
        if (id > 0) {
          fixtureById[id] = raw;
        }
      }
      for (final item in entries) {
        final raw = fixtureById[item.fixtureId];
        if (raw == null || raw['fixture'] is! Map || raw['goals'] is! Map) {
          continue;
        }
        final status = (raw['fixture'] as Map)['status'];
        if (status is! Map || status['short']?.toString() != 'FT') {
          continue;
        }
        final goals = raw['goals'] as Map;
        final home = SmartBetScorerGoalEventVerifier._toInt(goals['home']);
        final away = SmartBetScorerGoalEventVerifier._toInt(goals['away']);
        if (goals['home'] == null || goals['away'] == null) {
          continue;
        }
        try {
          final events = await fetchEvents(item.fixtureId);
          final credited = SmartBetScorerGoalEventVerifier.verifiedGoals(
            events: events,
            homeGoals: home,
            awayGoals: away,
          );
          if (credited == null) {
            continue;
          }
          if (await store.settleFixture(
                fixtureId: item.fixtureId,
                goalsByPlayer: credited,
                resolvedAt: at,
              ) >
              0) {
            settled++;
          }
        } catch (_) {
          // La partita resta in sospeso, mai marcata erroneamente persa.
        }
      }
    }
    return settled;
  }
}

class SmartBetScorerCalibrationResult {
  final double probability;
  final bool applied;
  final int validatedFixtures;

  const SmartBetScorerCalibrationResult({
    required this.probability,
    required this.applied,
    required this.validatedFixtures,
  });
}

/// Calibrazione specifica della probabilita' "segna almeno 1 gol".
/// Addestramento cronologico 70%, verifica prospettica 30% e su meta' di
/// validazione. Richiede almeno 100 fixture DISTINTE e 14 giorni distinti.
/// Non condivide la calibrazione dei mercati partita con quella dei giocatori.
class SmartBetScorerCalibrationService {
  const SmartBetScorerCalibrationService._();

  static SmartBetScorerCalibrationResult evaluate({
    required List<SmartBetScorerLearningRecord> records,
    required DateTime startedAt,
    required int currentFixtureId,
    required double originalProbability,
    required bool optedIn,
  }) {
    final unchanged = SmartBetScorerCalibrationResult(
      probability: originalProbability,
      applied: false,
      validatedFixtures: 0,
    );
    if (!optedIn ||
        currentFixtureId <= 0 ||
        !originalProbability.isFinite ||
        originalProbability < 0 ||
        originalProbability > 1) {
      return unchanged;
    }
    final cutoff = startedAt.toUtc();
    final distinct = <int, SmartBetScorerLearningRecord>{};
    final eligible =
        records
            .where(
              (r) =>
                  r.isResolved &&
                  r.resolvedAt!.toUtc().isBefore(cutoff) &&
                  r.predictedAt.toUtc().isBefore(r.kickoffAt.toUtc()) &&
                  r.fixtureId != currentFixtureId,
            )
            .toList()
          ..sort((a, b) {
            final result = a.predictedAt.compareTo(b.predictedAt);
            return result != 0 ? result : a.playerId.compareTo(b.playerId);
          });
    for (final record in eligible) {
      // Una previsione per partita, evitando falsa indipendenza.
      distinct.putIfAbsent(record.fixtureId, () => record);
    }
    final samples = distinct.values.toList();
    if (samples.length < 100) {
      return unchanged;
    }
    final days = samples.map((r) {
      final at = r.predictedAt.toUtc();
      return '${at.year}-${at.month}-${at.day}';
    }).toSet();
    if (days.length < 14) {
      return unchanged;
    }

    final countTraining = (samples.length * 0.70).floor();
    final training = samples.take(countTraining).toList();
    final validation = samples.skip(countTraining).toList();
    if (training.length < 70 || validation.length < 30) {
      return unchanged;
    }
    double mean(
      List<SmartBetScorerLearningRecord> list,
      double Function(SmartBetScorerLearningRecord) project,
    ) => list.map(project).reduce((a, b) => a + b) / list.length;
    final observed = mean(training, (r) => r.scored ? 1.0 : 0.0);
    final predicted = mean(training, (r) => r.originalProbability);
    final bias =
        ((observed - predicted) * (training.length / (training.length + 100.0)))
            .clamp(-0.10, 0.10)
            .toDouble();
    if (bias.abs() < 0.005) {
      return unchanged;
    }
    double gain(List<SmartBetScorerLearningRecord> cases) {
      return mean(cases, (r) {
        final y = r.scored ? 1.0 : 0.0;
        final raw = r.originalProbability;
        final corrected = (raw + bias).clamp(0.0, 1.0).toDouble();
        return math.pow(raw - y, 2).toDouble() -
            math.pow(corrected - y, 2).toDouble();
      });
    }

    final middle = validation.length ~/ 2;
    if (gain(validation) < 0.002 ||
        gain(validation.take(middle).toList()) < 0.001 ||
        gain(validation.skip(middle).toList()) < 0.001) {
      return unchanged;
    }
    final corrected = (originalProbability + bias).clamp(0.0, 1.0).toDouble();
    if ((corrected - originalProbability).abs() < 0.005) {
      return unchanged;
    }
    return SmartBetScorerCalibrationResult(
      probability: corrected,
      applied: true,
      validatedFixtures: validation.length,
    );
  }
}
