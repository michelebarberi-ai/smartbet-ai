import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_analysis_history_store.dart';

/// Snapshot minimale per l'eventuale invio futuro al server.
/// Non contiene risultati, identita dell'utente o credenziali.
class GoalVdLineLearningDraft {
  final int fixtureId;
  final String engine;
  final String market;
  final double probability;
  final DateTime firstSeenAt;
  final DateTime kickoffAt;

  const GoalVdLineLearningDraft({
    required this.fixtureId,
    required this.engine,
    required this.market,
    required this.probability,
    required this.firstSeenAt,
    required this.kickoffAt,
  });

  String get key => '$engine|$fixtureId|$market';

  Map<String, Object> toJson() => {
    'fixtureId': fixtureId,
    'engine': engine,
    'market': market,
    'probability': probability,
    'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
    'kickoffAt': kickoffAt.toUtc().toIso8601String(),
  };

  static GoalVdLineLearningDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['fixtureId'];
    final engine = raw['engine'];
    final market = raw['market'];
    final probability = raw['probability'];
    final first = DateTime.tryParse(raw['firstSeenAt']?.toString() ?? '');
    final kickoff = DateTime.tryParse(raw['kickoffAt']?.toString() ?? '');

    if (id is! int ||
        id <= 0 ||
        (engine != 'smartBet' && engine != 'diego') ||
        market is! String ||
        market.trim().isEmpty ||
        probability is! num ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1 ||
        first == null ||
        kickoff == null ||
        !first.isBefore(kickoff)) {
      return null;
    }

    return GoalVdLineLearningDraft(
      fixtureId: id,
      engine: engine as String,
      market: market,
      probability: probability.toDouble(),
      firstSeenAt: first.toUtc(),
      kickoffAt: kickoff.toUtc(),
    );
  }
}

/// P23B1: opt-in e coda *solo locale*. Nessuna chiamata HTTP.
///
/// - Il consenso e disattivato di default.
/// - Nessun backfill dello storico precedente al consenso.
/// - Le previsioni vengono copiate una volta sola (first-seen immutabile).
/// - Non si conserva alcun risultato o dato identificativo.
/// - I record scaduti sono eliminati, mai inviati dopo il kickoff.
/// - La revoca cancella immediatamente tutte le bozze pendenti.
class GoalVdLineCentralLearningOutbox {
  GoalVdLineCentralLearningOutbox({
    SharedPreferences? preferences,
    DateTime Function()? clock,
  }) : _preferences = preferences,
       _clock = clock ?? DateTime.now;

  static final GoalVdLineCentralLearningOutbox instance =
      GoalVdLineCentralLearningOutbox();

  static const _consentKey = 'goalvdline_central_learning_consent_v1';
  static const _consentSinceKey = 'goalvdline_central_learning_since_v1';
  static const _draftsKey = 'goalvdline_central_learning_drafts_v1';
  static const _kickoffMargin = Duration(minutes: 2);
  static const _maxPending = 500;

  SharedPreferences? _preferences;
  final DateTime Function() _clock;
  bool _initialized = false;
  bool _consent = false;
  DateTime? _consentSince;
  final List<GoalVdLineLearningDraft> _pending = [];

  bool get consentGranted => _initialized && _consent;
  int get pendingCount => _pending.length;
  List<GoalVdLineLearningDraft> get pendingDrafts =>
      List.unmodifiable(_pending);

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    final since = DateTime.tryParse(prefs.getString(_consentSinceKey) ?? '');
    _consentSince = since?.toUtc();
    _consent = prefs.getBool(_consentKey) == true && _consentSince != null;

    _pending.clear();
    if (_consent) {
      try {
        final raw = jsonDecode(prefs.getString(_draftsKey) ?? '[]');
        if (raw is List) {
          final seen = <String>{};
          for (final entry in raw) {
            final draft = GoalVdLineLearningDraft.fromJson(entry);
            if (draft != null &&
                !draft.firstSeenAt.isBefore(_consentSince!) &&
                seen.add(draft.key) &&
                _pending.length < _maxPending) {
              _pending.add(draft);
            }
          }
        }
      } catch (_) {
        // Fail closed: dati corrotti non vengono recuperati o inviati.
        _pending.clear();
      }
    }
    _initialized = true;
    await _removeExpiredAndPersist();
  }

  Future<void> setConsent(bool enabled) async {
    await initialize();
    if (_consent == enabled) return;
    final prefs = _preferences!;
    if (!enabled) {
      // Prima revoca, poi cancella: in caso di errore non resta un opt-in attivo.
      await prefs.setBool(_consentKey, false);
      _consent = false;
      _consentSince = null;
      _pending.clear();
      await prefs.remove(_draftsKey);
      await prefs.remove(_consentSinceKey);
      return;
    }
    // Un nuovo consenso non autorizza la raccolta dello storico pregresso.
    final start = _clock().toUtc();
    _pending.clear();
    await prefs.remove(_draftsKey);
    await prefs.setString(_consentSinceKey, start.toIso8601String());
    await prefs.setBool(_consentKey, true);
    _consentSince = start;
    _consent = true;
  }

  Future<bool> captureIfEligible(SmartBetAnalysisRecord? record) async {
    await initialize();
    if (!_consent || record == null || _consentSince == null) return false;
    final now = _clock().toUtc();
    await _removeExpiredAndPersist();

    final probability = record.probability;
    if (!record.prospectiveEligible ||
        record.status != SmartBetAnalysisStatus.pending ||
        probability == null ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1 ||
        record.fixtureId <= 0 ||
        record.market.trim().isEmpty ||
        record.firstSeenAt.toUtc().isBefore(_consentSince!) ||
        record.firstSeenAt.toUtc().isAfter(
          now.add(const Duration(minutes: 1)),
        ) ||
        !record.matchDate.toUtc().isAfter(now.add(_kickoffMargin))) {
      return false;
    }

    if (_pending.any((draft) => draft.key == record.key)) return false;
    if (_pending.length >= _maxPending) return false;

    _pending.add(
      GoalVdLineLearningDraft(
        fixtureId: record.fixtureId,
        engine: record.engine.name,
        market: record.market,
        probability: probability,
        firstSeenAt: record.firstSeenAt.toUtc(),
        kickoffAt: record.matchDate.toUtc(),
      ),
    );
    await _saveDrafts();
    return true;
  }

  /// Per la P23B2: lascia solo bozze ancora accettabili prima del kickoff.
  /// Non invia dati. L'autenticazione e il trasporto saranno un modulo separato.
  Future<List<GoalVdLineLearningDraft>> eligibleLocalDrafts() async {
    await initialize();
    if (!_consent) return const [];
    await _removeExpiredAndPersist();
    return List.unmodifiable(_pending);
  }

  /// Rimuove solo draft esattamente confermati dall'endpoint mobile.
  /// Prima persiste il nuovo stato; se fallisce, la vecchia coda resta intatta.
  Future<void> confirmDelivered(
    Iterable<GoalVdLineLearningDraft> confirmed,
  ) async {
    await initialize();
    if (!_consent) return;
    final accepted = confirmed
        .map((draft) => jsonEncode(draft.toJson()))
        .toSet();
    final retained = _pending
        .where((draft) => !accepted.contains(jsonEncode(draft.toJson())))
        .toList();
    if (retained.length == _pending.length) return;
    final prefs = _preferences!;
    final bool saved;
    if (retained.isEmpty) {
      saved = await prefs.remove(_draftsKey);
    } else {
      saved = await prefs.setString(
        _draftsKey,
        jsonEncode(retained.map((draft) => draft.toJson()).toList()),
      );
    }
    if (!saved) throw StateError('Conferma locale non persistita.');
    _pending
      ..clear()
      ..addAll(retained);
  }

  Future<void> _removeExpiredAndPersist() async {
    final threshold = _clock().toUtc().add(_kickoffMargin);
    final before = _pending.length;
    _pending.removeWhere((draft) => !draft.kickoffAt.isAfter(threshold));
    if (before != _pending.length || !_consent) {
      await _saveDrafts();
    }
  }

  Future<void> _saveDrafts() async {
    final prefs = _preferences!;
    if (!_consent || _pending.isEmpty) {
      await prefs.remove(_draftsKey);
      return;
    }
    await prefs.setString(
      _draftsKey,
      jsonEncode(_pending.map((draft) => draft.toJson()).toList()),
    );
  }
}
