import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'team_data_resolver.dart';

class SharedPreferencesTeamLeagueCacheStore implements TeamLeagueCacheStore {
  SharedPreferencesTeamLeagueCacheStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _storageKey = 'smartbet_team_league_cache_v1';

  static const int _schemaVersion = 1;

  /// Se cambia la logica con cui TeamDataResolver sceglie
  /// il "campionato domestico principale", cambiare firma.
  static const String _resolverSignature =
      'team_league_resolver_v1_main_league_selector_v1';

  static const int _maxEntries = 1024;

  final SharedPreferencesAsync _preferences;

  Future<void> _queue = Future<void>.value();

  @override
  Future<ResolvedTeamLeague?> read({
    required int teamId,
    required int season,
  }) async {
    await _queue;

    if (teamId <= 0 || season <= 0) {
      return null;
    }

    try {
      final root = await _loadRoot();

      final entriesRaw = root['entries'];

      if (entriesRaw is! Map) {
        return null;
      }

      final raw = entriesRaw[_entryKey(teamId, season)];

      if (raw is! Map) {
        return null;
      }

      final data = Map<String, dynamic>.from(raw);

      if (data['resolverSignature']?.toString() != _resolverSignature) {
        return null;
      }

      final storedTeamId = _toInt(data['teamId']);

      final storedSeason = _toInt(data['season']);

      final leagueId = _toInt(data['leagueId']);

      final teamName = data['teamName']?.toString().trim() ?? '';

      final leagueName = data['leagueName']?.toString().trim() ?? '';

      if (storedTeamId != teamId ||
          storedSeason != season ||
          leagueId <= 0 ||
          teamName.isEmpty ||
          leagueName.isEmpty) {
        return null;
      }

      return ResolvedTeamLeague(
        teamId: storedTeamId,
        teamName: teamName,
        season: storedSeason,
        leagueId: leagueId,
        leagueName: leagueName,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(ResolvedTeamLeague value) {
    return _enqueue(() async {
      if (value.teamId <= 0 ||
          value.season <= 0 ||
          value.leagueId <= 0 ||
          value.teamName.trim().isEmpty ||
          value.leagueName.trim().isEmpty) {
        return;
      }

      final root = await _loadRoot();

      final entriesRaw = root['entries'];

      final entries = entriesRaw is Map
          ? Map<String, dynamic>.from(entriesRaw)
          : <String, dynamic>{};

      final now = DateTime.now().toUtc().toIso8601String();

      entries[_entryKey(value.teamId, value.season)] = {
        'teamId': value.teamId,
        'teamName': value.teamName,
        'season': value.season,
        'leagueId': value.leagueId,
        'leagueName': value.leagueName,
        'savedAt': now,
        'resolverSignature': _resolverSignature,
      };

      _trim(entries);

      await _preferences.setString(
        _storageKey,
        jsonEncode({'schemaVersion': _schemaVersion, 'entries': entries}),
      );
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
    return {'schemaVersion': _schemaVersion, 'entries': <String, dynamic>{}};
  }

  void _trim(Map<String, dynamic> entries) {
    if (entries.length <= _maxEntries) {
      return;
    }

    final ordered = entries.entries.toList()
      ..sort((a, b) {
        final aDate = _savedAt(a.value);

        final bDate = _savedAt(b.value);

        return bDate.compareTo(aDate);
      });

    final keep = ordered.take(_maxEntries).map((entry) => entry.key).toSet();

    entries.removeWhere((key, _) => !keep.contains(key));
  }

  DateTime _savedAt(dynamic value) {
    if (value is! Map) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    return DateTime.tryParse(value['savedAt']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  String _entryKey(int teamId, int season) {
    return '$teamId|$season';
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

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());

    _queue = next.catchError((_) {});

    return next;
  }
}
