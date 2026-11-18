import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_result.dart';
import '../models/match_model.dart';
import 'diego_ai_service.dart';
import 'goalvdline_third_brain_own_input_service.dart';
import 'goalvdline_third_brain_service.dart';
import 'smartbet_analysis_history_store.dart';
import 'smartbet_analysis_market_settlement.dart';

/// Fixed pre-match research market, not a coupon recommendation.
class GoalVdLineBenchmarkMarket {
  final String market;
  final double smartBet;
  final double diego;
  final double thirdBrain;

  const GoalVdLineBenchmarkMarket({
    required this.market,
    required this.smartBet,
    required this.diego,
    required this.thirdBrain,
  });

  Map<String, dynamic> toJson() => {
    'market': market,
    'smartBet': smartBet,
    'diego': diego,
    'thirdBrain': thirdBrain,
  };

  static GoalVdLineBenchmarkMarket? fromJson(dynamic input) {
    if (input is! Map) return null;
    final m = input['market']?.toString() ?? '';
    if (!GoalVdLineThreeEngineBenchmarkStore.fixedMarkets.contains(m)) {
      return null;
    }
    double? p(dynamic x) => x is num && x.isFinite &&
        x > 0 && x <= 1 ? x.toDouble() : null;
    final s = p(input['smartBet']);
    final d = p(input['diego']);
    final t = p(input['thirdBrain']);
    if (s == null || d == null || t == null) return null;
    return GoalVdLineBenchmarkMarket(
      market: m, smartBet: s, diego: d, thirdBrain: t,
    );
  }
}

/// Frozen, timestamped, local-only observation; no odds, results or PII.
/// Separate SharedPreferences key prevents contamination of coupon history,
/// MEI, existing shadow calibration and central learning uploads.
class GoalVdLineThreeEngineBenchmarkSnapshot {
  final int fixtureId;
  final DateTime kickoff;
  final DateTime firstSeenAt;
  final String homeTeam;
  final String awayTeam;
  final String league;
  final String country;
  final String thirdInputSource;
  final String thirdModelVersion;
  final List<GoalVdLineBenchmarkMarket> markets;

  const GoalVdLineThreeEngineBenchmarkSnapshot({
    required this.fixtureId,
    required this.kickoff,
    required this.firstSeenAt,
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    required this.country,
    required this.thirdInputSource,
    required this.thirdModelVersion,
    required this.markets,
  });

  Map<String, dynamic> toJson() => {
    'fixtureId': fixtureId,
    'kickoff': kickoff.toUtc().toIso8601String(),
    'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'league': league,
    'country': country,
    'thirdInputSource': thirdInputSource,
    'thirdModelVersion': thirdModelVersion,
    'markets': markets.map((e) => e.toJson()).toList(),
  };

  static GoalVdLineThreeEngineBenchmarkSnapshot? fromJson(dynamic input) {
    if (input is! Map) return null;
    final id = input['fixtureId'];
    final kickoff = DateTime.tryParse(input['kickoff']?.toString() ?? '');
    final firstSeen = DateTime.tryParse(input['firstSeenAt']?.toString() ?? '');
    final source = input['thirdInputSource']?.toString().trim() ?? '';
    final version = input['thirdModelVersion']?.toString().trim() ?? '';
    final league = input['league']?.toString().trim() ?? '';
    final country = input['country']?.toString().trim() ?? '';
    final marketsRaw = input['markets'];
    if (id is! int || id <= 0 || kickoff == null || firstSeen == null ||
        source.isEmpty || version.isEmpty || league.isEmpty ||
        country.isEmpty || marketsRaw is! List ||
        !firstSeen.toUtc().isBefore(
          kickoff.toUtc().subtract(const Duration(minutes: 2)),
        )) {
      return null;
    }
    final markets = marketsRaw.map(GoalVdLineBenchmarkMarket.fromJson)
        .whereType<GoalVdLineBenchmarkMarket>().toList();
    if (markets.isEmpty ||
        markets.map((m) => m.market).toSet().length != markets.length) {
      return null;
    }
    return GoalVdLineThreeEngineBenchmarkSnapshot(
      fixtureId: id,
      kickoff: kickoff.toUtc(),
      firstSeenAt: firstSeen.toUtc(),
      homeTeam: input['homeTeam']?.toString() ?? '',
      awayTeam: input['awayTeam']?.toString() ?? '',
      league: league,
      country: country,
      thirdInputSource: source,
      thirdModelVersion: version,
      markets: List.unmodifiable(markets),
    );
  }
}

class GoalVdLineThreeEngineBenchmarkStore {
  GoalVdLineThreeEngineBenchmarkStore({SharedPreferences? preferences})
      : _preferences = preferences;

  static const storageKey = 'goalvdline_three_engine_fixed_benchmark_v1';
  static const int maxSnapshots = 1800;

  /// Fixed in code BEFORE kickoff, not selected by probability or odds.
  static const List<String> fixedMarkets = [
    '1', 'X', '2', 'GOAL', 'NO GOAL',
    'OVER 1.5', 'UNDER 1.5', 'OVER 2.5', 'UNDER 2.5',
  ];

  SharedPreferences? _preferences;
  final List<GoalVdLineThreeEngineBenchmarkSnapshot> _snapshots = [];
  bool _initialized = false;
  List<GoalVdLineThreeEngineBenchmarkSnapshot> get snapshots =>
      List.unmodifiable(_snapshots);

  Future<void> initialize() async {
    if (_initialized) return;
    _preferences ??= await SharedPreferences.getInstance();
    try {
      final saved = _preferences!.getString(storageKey);
      if (saved != null) {
        final decoded = jsonDecode(saved);
        if (decoded is List) {
          final unique = <int>{};
          for (final item in decoded) {
            final snapshot =
                GoalVdLineThreeEngineBenchmarkSnapshot.fromJson(item);
            if (snapshot != null && unique.add(snapshot.fixtureId)) {
              _snapshots.add(snapshot);
            }
          }
        }
      }
    } catch (_) {
      // Corrupt research cache must never affect the live predictions.
      _snapshots.clear();
    }
    _initialized = true;
  }

  Future<bool> freeze(GoalVdLineThreeEngineBenchmarkSnapshot snapshot) async {
    await initialize();
    if (snapshot.fixtureId <= 0 || snapshot.markets.isEmpty ||
        snapshot.league.trim().isEmpty || snapshot.country.trim().isEmpty ||
        snapshot.thirdInputSource.isEmpty || snapshot.thirdModelVersion.isEmpty ||
        !snapshot.firstSeenAt.toUtc().isBefore(
          snapshot.kickoff.toUtc().subtract(const Duration(minutes: 2)),
        )) {
      return false;
    }
    if (_snapshots.any((s) => s.fixtureId == snapshot.fixtureId)) {
      return false; // First observation is immutable, even across sources.
    }
    if (snapshot.markets.any((m) =>
        !fixedMarkets.contains(m.market) ||
        ![m.smartBet, m.diego, m.thirdBrain].every(
          (p) => p.isFinite && p > 0 && p <= 1,
        )) ||
        snapshot.markets.map((m) => m.market).toSet().length !=
            snapshot.markets.length) {
      return false;
    }
    _snapshots.add(snapshot);
    _snapshots.sort((a, b) => b.kickoff.compareTo(a.kickoff));
    if (_snapshots.length > maxSnapshots) {
      _snapshots.removeRange(maxSnapshots, _snapshots.length);
    }
    await _preferences!.setString(storageKey, jsonEncode(
      _snapshots.map((s) => s.toJson()).toList(),
    ));
    return true;
  }

  /// Read-only join to ALREADY verified fixture scores in existing history.
  /// This NEVER inserts benchmark picks into learning, MEI or a coupon.
  /// If outcome chronology or competing score reports disagree: exclude.
  List<SmartBetAnalysisRecord> verifiedPairedRecords({
    required Iterable<SmartBetAnalysisRecord> resultHistory,
    required DateTime asOf,
  }) {
    final cutoff = asOf.toUtc();
    final byFixture = <int, List<SmartBetAnalysisRecord>>{};
    for (final r in resultHistory) {
      (byFixture[r.fixtureId] ??= []).add(r);
    }
    final compared = <SmartBetAnalysisRecord>[];
    for (final snapshot in _snapshots) {
      if (snapshot.kickoff.isAfter(cutoff)) continue;
      final results = byFixture[snapshot.fixtureId] ?? const [];
      final valid = results.where((r) =>
          r.actualHomeGoals != null && r.actualAwayGoals != null &&
          r.actualHomeGoals! >= 0 && r.actualAwayGoals! >= 0 &&
          r.outcomeKnownBy != null &&
          r.outcomeKnownBy!.toUtc().isAfter(snapshot.kickoff) &&
          !r.outcomeKnownBy!.toUtc().isAfter(cutoff) &&
          r.matchDate.toUtc().isAtSameMomentAs(snapshot.kickoff) &&
          r.league.trim().toUpperCase() == snapshot.league.toUpperCase() &&
          r.country.trim().toUpperCase() == snapshot.country.toUpperCase() &&
          (r.status == SmartBetAnalysisStatus.correct ||
              r.status == SmartBetAnalysisStatus.wrong)).toList();
      if (valid.isEmpty) continue;
      final first = valid.first;
      final home = first.actualHomeGoals!;
      final away = first.actualAwayGoals!;
      // Reject any contradictory settled outcome in the device history.
      if (results.any((r) =>
          r.actualHomeGoals != null && r.actualAwayGoals != null &&
          (r.actualHomeGoals != home || r.actualAwayGoals != away ||
           !r.matchDate.toUtc().isAtSameMomentAs(snapshot.kickoff)))) {
        continue;
      }
      // Prefer earliest verified observation; never backdate a resolution.
      final outcomeKnownAt = valid.map((r) => r.outcomeKnownBy!.toUtc())
          .reduce((a, b) => a.isBefore(b) ? a : b);
      for (final market in snapshot.markets) {
        final outcome = SmartBetAnalysisMarketSettlement.evaluate(
          market: market.market, homeGoals: home, awayGoals: away,
        );
        if (outcome == SmartBetAnalysisSettlement.unsupported) continue;
        final status = outcome == SmartBetAnalysisSettlement.correct
            ? SmartBetAnalysisStatus.correct
            : SmartBetAnalysisStatus.wrong;
        for (final engine in SmartBetAnalysisEngine.values) {
          final p = switch (engine) {
            SmartBetAnalysisEngine.smartBet => market.smartBet,
            SmartBetAnalysisEngine.diego => market.diego,
            SmartBetAnalysisEngine.thirdBrain => market.thirdBrain,
          };
          compared.add(SmartBetAnalysisRecord(
            engine: engine,
            fixtureId: snapshot.fixtureId,
            homeTeam: snapshot.homeTeam,
            awayTeam: snapshot.awayTeam,
            league: snapshot.league,
            country: snapshot.country,
            matchDate: snapshot.kickoff,
            market: market.market,
            probability: p,
            smartScore: null,
            confidence: null,
            classification: 'FIXED_BENCHMARK_SHADOW',
            qualified: false,
            inputSource: engine == SmartBetAnalysisEngine.thirdBrain
                ? snapshot.thirdInputSource : null,
            modelVersion: engine == SmartBetAnalysisEngine.thirdBrain
                ? snapshot.thirdModelVersion : null,
            sources: const [SmartBetAnalysisSource.analysis],
            prospectiveEligible: true,
            status: status,
            actualHomeGoals: home,
            actualAwayGoals: away,
            firstSeenAt: snapshot.firstSeenAt,
            lastSeenAt: outcomeKnownAt,
            resolvedAt: outcomeKnownAt,
          ));
        }
      }
    }
    return List.unmodifiable(compared);
  }
}

/// Uses probabilities already calculated for the current real fixture.
class GoalVdLineThreeEngineBenchmarkCaptureService {
  GoalVdLineThreeEngineBenchmarkCaptureService({required this.store});

  final GoalVdLineThreeEngineBenchmarkStore store;

  Future<bool> capture({
    required MatchModel match,
    required AnalysisResult smartBet,
    required DiegoAiAnalysis? diego,
    DateTime? recordedAt,
  }) async {
    final now = (recordedAt ?? DateTime.now()).toUtc();
    final kickoff = DateTime.tryParse(match.date)?.toUtc();
    if (diego == null || kickoff == null || match.fixtureId <= 0 ||
        !now.isBefore(kickoff.subtract(const Duration(minutes: 2))) ||
        match.league.trim().isEmpty || match.country.trim().isEmpty ||
        smartBet.smartScore <= 0 || smartBet.dataConfidence <= 0) {
      return false;
    }
    await store.initialize();
    if (store.snapshots.any((s) => s.fixtureId == match.fixtureId)) {
      return false;
    }
    final ownInput = const GoalVdLineThirdBrainOwnInputService()
        .fromCachedFixtureHistory(match: match, observedAt: now);
    final third = const GoalVdLineThirdBrainService().evaluate(
      smartBet: smartBet, diego: diego, ownInput: ownInput,
    );
    if (third == null || third.dataConfidence == null ||
        third.dataConfidence! < 40) return false;

    final diegoMarkets = <String, double>{};
    final ambiguous = <String>{};
    for (final m in diego.markets) {
      final name = normalizeAnalysisMarket(m.market);
      if (!GoalVdLineThreeEngineBenchmarkStore.fixedMarkets.contains(name) ||
          !m.probability.isFinite || m.probability <= 0 ||
          m.probability > 1) continue;
      if (diegoMarkets.containsKey(name)) ambiguous.add(name);
      diegoMarkets[name] = m.probability;
    }
    final entries = <GoalVdLineBenchmarkMarket>[];
    for (final market in GoalVdLineThreeEngineBenchmarkStore.fixedMarkets) {
      if (ambiguous.contains(market)) continue;
      final smartPercent = switch (market) {
        '1' => smartBet.homeProbability,
        'X' => smartBet.drawProbability,
        '2' => smartBet.awayProbability,
        'GOAL' => smartBet.goalProbability,
        'NO GOAL' => smartBet.noGoalProbability,
        'OVER 1.5' => smartBet.over15Probability,
        'UNDER 1.5' => smartBet.under15Probability,
        'OVER 2.5' => smartBet.over25Probability,
        'UNDER 2.5' => smartBet.under25Probability,
        _ => 0,
      };
      final d = diegoMarkets[market];
      final t = third.forMarket(market)?.probability;
      // Zero in AnalysisResult is also the default "not computed" value.
      // Skip it rather than recording a fabricated 0% forecast.
      if (smartPercent <= 0 || smartPercent > 100 ||
          d == null || t == null || !t.isFinite || t <= 0 || t > 1) {
        continue;
      }
      entries.add(GoalVdLineBenchmarkMarket(
        market: market,
        smartBet: smartPercent / 100.0,
        diego: d,
        thirdBrain: t,
      ));
    }
    if (entries.isEmpty) return false;
    return store.freeze(GoalVdLineThreeEngineBenchmarkSnapshot(
      fixtureId: match.fixtureId,
      kickoff: kickoff,
      firstSeenAt: now,
      homeTeam: match.homeTeam,
      awayTeam: match.awayTeam,
      league: match.league,
      country: match.country,
      thirdInputSource: third.inputSource,
      thirdModelVersion: third.modelVersion,
      markets: List.unmodifiable(entries),
    ));
  }
}
