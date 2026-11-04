import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'smartbet_analysis_history_store.dart';

/// P23B3: fotografia retrospettiva, distinta dalla coda live P23B1.
///
/// NON e' una prova server-side che la previsione sia stata fatta prima
/// della partita. Non e' una fonte attendibile di risultati sportivi.
/// Nessun invio HTTP o aggiornamento delle probabilita' e' implementato qui.
class GoalVdLineHistoricalDraft {
  final int fixtureId;
  final String engine;
  final String market;
  final double probability;
  final DateTime firstSeenAt;
  final DateTime kickoffAt;

  /// Solo indicazione locale; il futuro backend deve verificare l'esito.
  final String localStatusHint;

  const GoalVdLineHistoricalDraft({
    required this.fixtureId,
    required this.engine,
    required this.market,
    required this.probability,
    required this.firstSeenAt,
    required this.kickoffAt,
    required this.localStatusHint,
  });

  String get key => '$engine|$fixtureId|$market';

  Map<String, Object> toJson() => {
    'kind': 'retrospective_unverified_v1',
    'fixtureId': fixtureId,
    'engine': engine,
    'market': market,
    'probability': probability,
    'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
    'kickoffAt': kickoffAt.toUtc().toIso8601String(),
    'localStatusHint': localStatusHint,
  };

  static GoalVdLineHistoricalDraft? fromJson(Object? raw) {
    if (raw is! Map || raw['kind'] != 'retrospective_unverified_v1') {
      return null;
    }
    final id = raw['fixtureId'];
    final engine = raw['engine'];
    final market = raw['market'];
    final probability = raw['probability'];
    final firstSeenAt = DateTime.tryParse(raw['firstSeenAt']?.toString() ?? '');
    final kickoffAt = DateTime.tryParse(raw['kickoffAt']?.toString() ?? '');
    final localStatusHint = raw['localStatusHint'];
    if (id is! int ||
        id <= 0 ||
        (engine != 'smartBet' && engine != 'diego') ||
        market is! String ||
        market.trim().isEmpty ||
        market != normalizeAnalysisMarket(market) ||
        probability is! num ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1 ||
        firstSeenAt == null ||
        kickoffAt == null ||
        !firstSeenAt.isBefore(kickoffAt) ||
        (localStatusHint != 'correct' &&
            localStatusHint != 'wrong' &&
            localStatusHint != 'pending')) {
      return null;
    }
    return GoalVdLineHistoricalDraft(
      fixtureId: id,
      engine: engine as String,
      market: market,
      probability: probability.toDouble(),
      firstSeenAt: firstSeenAt.toUtc(),
      kickoffAt: kickoffAt.toUtc(),
      localStatusHint: localStatusHint as String,
    );
  }
}

class GoalVdLineHistoricalAudit {
  final int total;
  final int uniqueFixtures;
  final int settledCandidates;
  final int awaitingResult;
  final int excluded;
  final int futureFixtures;

  const GoalVdLineHistoricalAudit({
    required this.total,
    required this.uniqueFixtures,
    required this.settledCandidates,
    required this.awaitingResult,
    required this.excluded,
    required this.futureFixtures,
  });

  int get preparable => settledCandidates + awaitingResult;
}

enum _HistoricEligibility { settled, awaitingResult, excluded, future }

/// Consenso separato alla PREPARAZIONE LOCALE dello storico pregresso.
/// L'eventuale trasmissione futura richiedera' un'ulteriore autorizzazione.
class GoalVdLineHistoricalLearningReview {
  GoalVdLineHistoricalLearningReview({
    SharedPreferences? preferences,
    DateTime Function()? clock,
  }) : _preferences = preferences,
       _clock = clock ?? DateTime.now;

  static final GoalVdLineHistoricalLearningReview instance =
      GoalVdLineHistoricalLearningReview();

  static const _consentKey = 'goalvdline_retro_local_consent_v1';
  static const _cutoffKey = 'goalvdline_retro_local_cutoff_v1';
  static const _snapshotsKey = 'goalvdline_retro_local_snapshots_v1';
  static const _maxSnapshots = 20000;

  SharedPreferences? _preferences;
  final DateTime Function() _clock;
  bool _initialized = false;
  bool _consent = false;
  DateTime? _cutoff;
  final List<GoalVdLineHistoricalDraft> _snapshots = [];

  bool get consentGranted => _initialized && _consent;
  int get preparedCount => _snapshots.length;
  List<GoalVdLineHistoricalDraft> get preparedDrafts =>
      List.unmodifiable(_snapshots);

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    final cutoff = DateTime.tryParse(prefs.getString(_cutoffKey) ?? '');
    _consent = prefs.getBool(_consentKey) == true && cutoff != null;
    _cutoff = _consent ? cutoff!.toUtc() : null;
    _snapshots.clear();
    if (_consent) {
      try {
        final raw = jsonDecode(prefs.getString(_snapshotsKey) ?? '[]');
        if (raw is List) {
          final seen = <String>{};
          for (final entry in raw) {
            final snapshot = GoalVdLineHistoricalDraft.fromJson(entry);
            if (snapshot != null &&
                !snapshot.firstSeenAt.isAfter(_cutoff!) &&
                !snapshot.kickoffAt.isAfter(_cutoff!) &&
                seen.add(snapshot.key) &&
                _snapshots.length < _maxSnapshots) {
              _snapshots.add(snapshot);
            }
          }
        }
      } catch (_) {
        // Fail closed: non si caricano dati corrotti.
        _snapshots.clear();
      }
    }
    _initialized = true;
  }

  GoalVdLineHistoricalAudit audit(
    Iterable<SmartBetAnalysisRecord> records, {
    DateTime? asOf,
  }) {
    final now = (asOf ?? _clock()).toUtc();
    final fixtures = <int>{};
    final keys = <String>{};
    var total = 0;
    var settled = 0;
    var awaiting = 0;
    var excluded = 0;
    var future = 0;
    for (final record in records) {
      total++;
      fixtures.add(record.fixtureId);
      if (!keys.add(record.key)) {
        excluded++;
        continue;
      }
      switch (_eligibility(record, now)) {
        case _HistoricEligibility.settled:
          settled++;
        case _HistoricEligibility.awaitingResult:
          awaiting++;
        case _HistoricEligibility.excluded:
          excluded++;
        case _HistoricEligibility.future:
          future++;
      }
    }
    return GoalVdLineHistoricalAudit(
      total: total,
      uniqueFixtures: fixtures.length,
      settledCandidates: settled,
      awaitingResult: awaiting,
      excluded: excluded,
      futureFixtures: future,
    );
  }

  /// Richiede una chiamata esplicita dall'interfaccia dopo conferma utente.
  /// La prima preparazione congela il cutoff: i successivi aggiornamenti non
  /// possono trasformare nuove previsioni in presunte previsioni pregresse.
  /// Salva solo copie minime, MAI nel normale outbox P23B1.
  Future<int> prepareFromHistory(
    Iterable<SmartBetAnalysisRecord> records,
  ) async {
    await initialize();
    final now = _clock().toUtc();
    final cutoff = _cutoff ?? now;
    final seen = _snapshots.map((item) => item.key).toSet();
    final next = List<GoalVdLineHistoricalDraft>.from(_snapshots);
    for (final record in records) {
      if (next.length >= _maxSnapshots) break;
      if (record.firstSeenAt.toUtc().isAfter(cutoff)) continue;
      if (record.matchDate.toUtc().isAfter(cutoff)) continue;
      final eligible = _eligibility(record, now);
      if (eligible != _HistoricEligibility.settled &&
          eligible != _HistoricEligibility.awaitingResult) {
        continue;
      }
      if (!seen.add(record.key)) continue;
      next.add(
        GoalVdLineHistoricalDraft(
          fixtureId: record.fixtureId,
          engine: record.engine.name,
          market: normalizeAnalysisMarket(record.market),
          probability: record.probability!,
          firstSeenAt: record.firstSeenAt.toUtc(),
          kickoffAt: record.matchDate.toUtc(),
          localStatusHint: record.status.name,
        ),
      );
    }
    final prefs = _preferences!;
    // Prima si prepara la copia. Non viene mai modificato lo storico originale.
    if (!await prefs.setString(
      _snapshotsKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    )) {
      throw StateError('Impossibile conservare la copia retrospettiva.');
    }
    if (!await prefs.setString(_cutoffKey, cutoff.toIso8601String())) {
      throw StateError('Impossibile conservare la data di consenso.');
    }
    if (!await prefs.setBool(_consentKey, true)) {
      throw StateError('Impossibile conservare il consenso locale.');
    }
    _consent = true;
    _cutoff = cutoff;
    _snapshots
      ..clear()
      ..addAll(next);
    return _snapshots.length;
  }

  /// Elimina esclusivamente le copie retrospettive, non lo storico personale.
  Future<void> deletePrepared() async {
    await initialize();
    final prefs = _preferences!;
    // Disattiva prima di eliminare, per evitare riutilizzi accidentali.
    if (!await prefs.setBool(_consentKey, false)) {
      throw StateError('Impossibile revocare il consenso locale.');
    }
    _consent = false;
    _cutoff = null;
    _snapshots.clear();
    await prefs.remove(_snapshotsKey);
    await prefs.remove(_cutoffKey);
  }

  _HistoricEligibility _eligibility(
    SmartBetAnalysisRecord record,
    DateTime now,
  ) {
    if (record.matchDate.toUtc().isAfter(now)) {
      return _HistoricEligibility.future;
    }
    final probability = record.probability;
    if (record.fixtureId <= 0 ||
        record.market.trim().isEmpty ||
        probability == null ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1 ||
        !record.prospectiveEligible ||
        !record.firstSeenAt.toUtc().isBefore(record.matchDate.toUtc()) ||
        record.firstSeenAt.toUtc().isAfter(now)) {
      return _HistoricEligibility.excluded;
    }
    if ((record.status == SmartBetAnalysisStatus.correct ||
            record.status == SmartBetAnalysisStatus.wrong) &&
        record.hasActualResult) {
      return _HistoricEligibility.settled;
    }
    if (record.status == SmartBetAnalysisStatus.pending &&
        !record.hasActualResult) {
      return _HistoricEligibility.awaitingResult;
    }
    return _HistoricEligibility.excluded;
  }
}
