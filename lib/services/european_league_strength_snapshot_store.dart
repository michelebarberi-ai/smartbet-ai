import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'european_league_strength_service.dart';

class SharedPreferencesEuropeanLeagueStrengthSnapshotStore
    implements EuropeanLeagueStrengthSnapshotStore {
  SharedPreferencesEuropeanLeagueStrengthSnapshotStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _storageKey =
      'smartbet_european_league_strength_snapshots_v1';

  static const int _schemaVersion = 1;

  /// IMPORTANTE:
  /// cambiare questa firma se cambia una parte sostanziale del modello:
  /// - pesi prev/qual/main;
  /// - lambda;
  /// - parser canonical 90';
  /// - definizione main stage;
  /// - evidence gate;
  /// - algoritmo rating/covarianza.
  static const String _modelSignature =
      'd2b2_ls_v1_prev1_qual05_main1_lambda3_gate1_c90v1_mainstagev1';

  static const int _maxEntries = 8;

  final SharedPreferencesAsync _preferences;

  Future<void> _queue = Future<void>.value();

  @override
  Future<EuropeanLeagueStrengthSnapshot?> read({
    required int currentSeason,
    required DateTime referenceDate,
  }) async {
    await _queue;

    if (currentSeason <= 0) {
      return null;
    }

    final cutoff = _dateOnly(referenceDate);

    try {
      final root = await _loadRoot();

      final entriesRaw = root['entries'];

      if (entriesRaw is! Map) {
        return null;
      }

      final key = _entryKey(currentSeason, cutoff);

      final entryRaw = entriesRaw[key];

      if (entryRaw is! Map) {
        return null;
      }

      final entry = Map<String, dynamic>.from(entryRaw);

      if (entry['modelSignature']?.toString() != _modelSignature) {
        return null;
      }

      final snapshotRaw = entry['snapshot'];

      if (snapshotRaw is! Map) {
        return null;
      }

      final snapshot = _snapshotFromJson(
        Map<String, dynamic>.from(snapshotRaw),
      );

      if (snapshot == null) {
        return null;
      }

      if (snapshot.currentSeason != currentSeason) {
        return null;
      }

      if (_dayKey(snapshot.referenceDate) != _dayKey(cutoff)) {
        return null;
      }

      return snapshot;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(EuropeanLeagueStrengthSnapshot snapshot) {
    return _enqueue(() async {
      if (snapshot.currentSeason <= 0) {
        return;
      }

      final encoded = _snapshotToJson(snapshot);

      if (encoded == null) {
        return;
      }

      final root = await _loadRoot();

      final existingEntries = root['entries'];

      final entries = existingEntries is Map
          ? Map<String, dynamic>.from(existingEntries)
          : <String, dynamic>{};

      final key = _entryKey(snapshot.currentSeason, snapshot.referenceDate);

      entries[key] = {
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'modelSignature': _modelSignature,
        'snapshot': encoded,
      };

      _trimEntries(entries);

      final data = <String, dynamic>{
        'schemaVersion': _schemaVersion,
        'entries': entries,
      };

      await _preferences.setString(_storageKey, jsonEncode(data));
    });
  }

  Future<void> clear() {
    return _enqueue(() async {
      await _preferences.remove(_storageKey);
    });
  }

  Future<Map<String, dynamic>> _loadRoot() async {
    final raw = await _preferences.getString(_storageKey);

    if (raw == null || raw.trim().isEmpty) {
      return _emptyRoot();
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return _emptyRoot();
      }

      final root = Map<String, dynamic>.from(decoded);

      if (_toInt(root['schemaVersion']) != _schemaVersion) {
        return _emptyRoot();
      }

      return root;
    } catch (_) {
      return _emptyRoot();
    }
  }

  Map<String, dynamic> _emptyRoot() {
    return <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'entries': <String, dynamic>{},
    };
  }

  void _trimEntries(Map<String, dynamic> entries) {
    if (entries.length <= _maxEntries) {
      return;
    }

    final ordered = entries.entries.toList()
      ..sort((a, b) {
        final aDate = _entrySavedAt(a.value);
        final bDate = _entrySavedAt(b.value);

        return bDate.compareTo(aDate);
      });

    final keep = ordered.take(_maxEntries).map((entry) => entry.key).toSet();

    entries.removeWhere((key, _) => !keep.contains(key));
  }

  DateTime _entrySavedAt(dynamic value) {
    if (value is! Map) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    return DateTime.tryParse(value['savedAt']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Map<String, dynamic>? _snapshotToJson(
    EuropeanLeagueStrengthSnapshot snapshot,
  ) {
    final covariance = _encodeCovariance(snapshot.ratingCovariance);

    if (covariance == null) {
      return null;
    }

    final leagues = <Map<String, dynamic>>[];

    for (final league in snapshot.leagues) {
      if (!league.rating.isFinite ||
          !league.weightedEvidence.isFinite ||
          (league.standardError != null && !league.standardError!.isFinite) ||
          (league.confidence != null && !league.confidence!.isFinite)) {
        return null;
      }

      leagues.add({
        'leagueId': league.leagueId,
        'leagueName': league.leagueName,
        'rating': league.rating,
        'standardError': league.standardError,
        'previousMainMatches': league.previousMainMatches,
        'currentQualifyingMatches': league.currentQualifyingMatches,
        'currentMainMatches': league.currentMainMatches,
        'uniqueOpposingLeagues': league.uniqueOpposingLeagues,
        'weightedEvidence': league.weightedEvidence,
        'confidence': league.confidence,
      });
    }

    return {
      'currentSeason': snapshot.currentSeason,
      'referenceDate': snapshot.referenceDate.toUtc().toIso8601String(),
      'firstMainStageDate': snapshot.firstMainStageDate
          .toUtc()
          .toIso8601String(),
      'previousMainFixtures': snapshot.previousMainFixtures,
      'currentQualifyingFixtures': snapshot.currentQualifyingFixtures,
      'currentMainFixtures': snapshot.currentMainFixtures,
      'ambiguousScoreFixtures': snapshot.ambiguousScoreFixtures,
      'unfinishedPastFixtures': snapshot.unfinishedPastFixtures,
      'unresolvedLeagueFixtures': snapshot.unresolvedLeagueFixtures,
      'sameLeagueFixtures': snapshot.sameLeagueFixtures,
      'fallbackTeamResolutions': snapshot.fallbackTeamResolutions,
      'leagues': leagues,
      'covariance': covariance,
    };
  }

  EuropeanLeagueStrengthSnapshot? _snapshotFromJson(Map<String, dynamic> json) {
    try {
      final currentSeason = _toInt(json['currentSeason']);

      final referenceDate = DateTime.tryParse(
        json['referenceDate']?.toString() ?? '',
      );

      final firstMainStageDate = DateTime.tryParse(
        json['firstMainStageDate']?.toString() ?? '',
      );

      if (currentSeason <= 0 ||
          referenceDate == null ||
          firstMainStageDate == null) {
        return null;
      }

      final leaguesRaw = json['leagues'];

      if (leaguesRaw is! List || leaguesRaw.isEmpty) {
        return null;
      }

      final leagues = <EuropeanLeagueStrength>[];

      for (final item in leaguesRaw) {
        if (item is! Map) {
          return null;
        }

        final data = Map<String, dynamic>.from(item);

        final leagueId = _toInt(data['leagueId']);

        final leagueName = data['leagueName']?.toString().trim() ?? '';

        final rating = _nullableDouble(data['rating']);

        final standardError = _nullableDouble(data['standardError']);

        final weightedEvidence = _nullableDouble(data['weightedEvidence']);

        final confidence = _nullableDouble(data['confidence']);

        if (leagueId <= 0 ||
            leagueName.isEmpty ||
            rating == null ||
            weightedEvidence == null) {
          return null;
        }

        if (!rating.isFinite ||
            !weightedEvidence.isFinite ||
            (standardError != null && !standardError.isFinite) ||
            (confidence != null && !confidence.isFinite)) {
          return null;
        }

        leagues.add(
          EuropeanLeagueStrength(
            leagueId: leagueId,
            leagueName: leagueName,
            rating: rating,
            standardError: standardError,
            previousMainMatches: _toInt(data['previousMainMatches']),
            currentQualifyingMatches: _toInt(data['currentQualifyingMatches']),
            currentMainMatches: _toInt(data['currentMainMatches']),
            uniqueOpposingLeagues: _toInt(data['uniqueOpposingLeagues']),
            weightedEvidence: weightedEvidence,
            confidence: confidence,
          ),
        );
      }

      final covarianceRaw = json['covariance'];

      if (covarianceRaw is! Map) {
        return null;
      }

      final covariance = _decodeCovariance(
        Map<String, dynamic>.from(covarianceRaw),
      );

      if (covariance == null) {
        return null;
      }

      final leagueIds = leagues.map((league) => league.leagueId).toSet();

      if (!leagueIds.every(covariance.containsKey)) {
        return null;
      }

      leagues.sort((a, b) => b.rating.compareTo(a.rating));

      return EuropeanLeagueStrengthSnapshot(
        currentSeason: currentSeason,
        referenceDate: referenceDate.toUtc(),
        firstMainStageDate: firstMainStageDate.toUtc(),
        previousMainFixtures: _toInt(json['previousMainFixtures']),
        currentQualifyingFixtures: _toInt(json['currentQualifyingFixtures']),
        currentMainFixtures: _toInt(json['currentMainFixtures']),
        ambiguousScoreFixtures: _toInt(json['ambiguousScoreFixtures']),
        unfinishedPastFixtures: _toInt(json['unfinishedPastFixtures']),
        unresolvedLeagueFixtures: _toInt(json['unresolvedLeagueFixtures']),
        sameLeagueFixtures: _toInt(json['sameLeagueFixtures']),
        fallbackTeamResolutions: _toInt(json['fallbackTeamResolutions']),
        ratingCovariance: covariance,
        leagues: List.unmodifiable(leagues),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _encodeCovariance(
    Map<int, Map<int, double>> covariance,
  ) {
    final leagueIds = covariance.keys.toList()..sort();

    if (leagueIds.isEmpty) {
      return null;
    }

    final upper = <double>[];

    for (var i = 0; i < leagueIds.length; i++) {
      final firstId = leagueIds[i];
      final row = covariance[firstId];

      if (row == null) {
        return null;
      }

      for (var j = i; j < leagueIds.length; j++) {
        final secondId = leagueIds[j];
        final value = row[secondId];

        if (value == null || !value.isFinite) {
          return null;
        }

        upper.add(value);
      }
    }

    return {'leagueIds': leagueIds, 'upper': upper};
  }

  Map<int, Map<int, double>>? _decodeCovariance(Map<String, dynamic> json) {
    final idsRaw = json['leagueIds'];
    final upperRaw = json['upper'];

    if (idsRaw is! List || upperRaw is! List || idsRaw.isEmpty) {
      return null;
    }

    final ids = <int>[];

    for (final item in idsRaw) {
      final value = _toInt(item);

      if (value <= 0 || ids.contains(value)) {
        return null;
      }

      ids.add(value);
    }

    final expectedLength = ids.length * (ids.length + 1) ~/ 2;

    if (upperRaw.length != expectedLength) {
      return null;
    }

    final result = <int, Map<int, double>>{
      for (final id in ids) id: <int, double>{},
    };

    var index = 0;

    for (var i = 0; i < ids.length; i++) {
      for (var j = i; j < ids.length; j++) {
        final value = _nullableDouble(upperRaw[index]);

        index++;

        if (value == null || !value.isFinite) {
          return null;
        }

        result[ids[i]]![ids[j]] = value;
        result[ids[j]]![ids[i]] = value;
      }
    }

    return {
      for (final entry in result.entries)
        entry.key: Map.unmodifiable(entry.value),
    };
  }

  String _entryKey(int currentSeason, DateTime referenceDate) {
    return '$currentSeason|'
        '${_dayKey(referenceDate)}|'
        '$_modelSignature';
  }

  DateTime _dateOnly(DateTime value) {
    final utc = value.toUtc();

    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  String _dayKey(DateTime value) {
    final utc = value.toUtc();

    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _nullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());

    _queue = next.catchError((_) {});

    return next;
  }
}
