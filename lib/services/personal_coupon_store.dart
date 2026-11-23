import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only personal slips. Separate from AI prediction accuracy records.
class PersonalCouponStore extends ChangeNotifier {
  PersonalCouponStore._();
  static final instance = PersonalCouponStore._();
  static const _key = 'goalvdline_personal_coupons_v1';
  final List<PersonalCoupon> _coupons = [];
  bool _loaded = false;

  List<PersonalCoupon> get coupons => List.unmodifiable(_coupons);

  Future<void> initialize() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as List<dynamic>;
        _coupons.addAll(data.map((e) => PersonalCoupon.fromJson(
            Map<String, dynamic>.from(e as Map))));
      } catch (e) {
        debugPrint('Personal coupon data could not be read: $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key, jsonEncode(
        _coupons.map((e) => e.toJson()).toList()));
    if (!saved) throw StateError('Salvataggio schedine personali non riuscito');
    notifyListeners();
  }

  Future<void> create(String name) async {
    await initialize();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _coupons.add(PersonalCoupon(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed,
      selections: [],
    ));
    await _save();
  }

  Future<void> rename(String id, String name) async {
    await initialize();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = _coupons.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _coupons[index] = _coupons[index].copyWith(name: trimmed);
    await _save();
  }

  Future<void> delete(String id) async {
    await initialize();
    _coupons.removeWhere((e) => e.id == id);
    await _save();
  }

  /// Returns false when the pick is already saved or the slip no longer exists.
  Future<bool> addSelection(String id, PersonalSelection selection) async {
    await initialize();
    final index = _coupons.indexWhere((e) => e.id == id);
    if (index < 0) return false;
    final coupon = _coupons[index];
    final marketKey = selection.market.trim().toLowerCase();
    if (coupon.selections.any((e) =>
        e.fixtureId == selection.fixtureId &&
        e.market.trim().toLowerCase() == marketKey)) {
      return false;
    }
    _coupons[index] = coupon.copyWith(
      selections: [...coupon.selections, selection],
    );
    await _save();
    return true;
  }

  /// User's market can be edited without overwriting the original saved pick.
  Future<bool> changeSelectionMarket(
    String couponId, String fixtureId, String originalMarket,
    String chosenMarket,
  ) async {
    await initialize();
    final changed = chosenMarket.trim();
    if (changed.isEmpty || changed.length > 90) return false;
    final index = _coupons.indexWhere((e) => e.id == couponId);
    if (index < 0) return false;
    final coupon = _coupons[index];
    final selectionIndex = coupon.selections.indexWhere((pick) =>
        pick.fixtureId == fixtureId && pick.market == originalMarket);
    if (selectionIndex < 0) return false;
    if (coupon.selections.any((pick) =>
        pick.fixtureId == fixtureId &&
        pick.market != originalMarket &&
        pick.currentMarket.trim().toLowerCase() == changed.toLowerCase())) {
      return false;
    }
    final selections = [...coupon.selections];
    selections[selectionIndex] = selections[selectionIndex].withChosenMarket(changed);
    _coupons[index] = coupon.copyWith(selections: selections);
    await _save();
    return true;
  }

  /// Persist only verified FT or regulation-time scores, shared across coupons.
  Future<int> registerVerifiedResults(
    Map<String, PersonalVerifiedScore> results,
  ) async {
    await initialize();
    if (results.isEmpty) return 0;
    var updated = 0;
    for (var i = 0; i < _coupons.length; i++) {
      final coupon = _coupons[i];
      final selections = coupon.selections.map((pick) {
        final score = results[pick.fixtureId];
        if (score == null) return pick;
        if (pick.verifiedHomeGoals == score.homeGoals &&
            pick.verifiedAwayGoals == score.awayGoals) return pick;
        updated++;
        return pick.withVerifiedScore(score);
      }).toList(growable: false);
      _coupons[i] = coupon.copyWith(selections: selections);
    }
    if (updated > 0) await _save();
    return updated;
  }

  Future<void> removeSelection(String id, String fixtureId, String market) async {
    await initialize();
    final index = _coupons.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final coupon = _coupons[index];
    _coupons[index] = coupon.copyWith(
      selections: coupon.selections.where((e) =>
          !(e.fixtureId == fixtureId && e.market == market)).toList(),
    );
    await _save();
  }
}

class PersonalCoupon {
  final String id;
  final String name;
  final List<PersonalSelection> selections;
  const PersonalCoupon({required this.id, required this.name, required this.selections});

  PersonalCoupon copyWith({String? name, List<PersonalSelection>? selections}) =>
      PersonalCoupon(id: id, name: name ?? this.name,
          selections: selections ?? this.selections);

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name,
    'selections': selections.map((e) => e.toJson()).toList(),
  };

  factory PersonalCoupon.fromJson(Map<String, dynamic> json) => PersonalCoupon(
    id: json['id'] as String,
    name: json['name'] as String,
    selections: ((json['selections'] as List<dynamic>?) ?? [])
        .map((e) => PersonalSelection.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

class PersonalSelection {
  final String fixtureId;
  final String match;
  final String market;
  final String source;
  final double? odds;
  /// Sporting probability on a 0-100 scale; not derived from bookmaker odds.
  final double? probability;
  /// Fixture metadata is snapshotted with each saved pick, without API calls.
  /// Nullable for coupons created before this schema extension.
  final String? country;
  final String? league;
  final DateTime? kickoffAt;
  final String? bookmaker;
  /// Null means the selected market is still the one initially saved.
  final String? chosenMarket;
  /// Independent top sporting pick, when the originating UI supplied it.
  final String? aiPrimaryMarket;
  final double? aiPrimaryProbability;
  /// Only from confirmed final fixture scores, not AI or user predictions.
  final int? verifiedHomeGoals;
  final int? verifiedAwayGoals;
  final DateTime? scoreVerifiedAt;
  final DateTime capturedAt;
  const PersonalSelection({required this.fixtureId, required this.match,
    required this.market, required this.source, required this.capturedAt,
    this.odds, this.probability, this.country, this.league, this.kickoffAt,
    this.bookmaker, this.chosenMarket, this.aiPrimaryMarket,
    this.aiPrimaryProbability, this.verifiedHomeGoals,
    this.verifiedAwayGoals, this.scoreVerifiedAt});

  String get currentMarket => chosenMarket ?? market;
  bool get editedByUser =>
      currentMarket.trim().toLowerCase() != market.trim().toLowerCase();
  double? get currentOdds => editedByUser ? null : odds;
  double? get currentProbability => editedByUser ? null : probability;

  PersonalSelection withChosenMarket(String newMarket) => PersonalSelection(
    fixtureId: fixtureId, match: match, market: market, source: source,
    capturedAt: capturedAt, odds: odds, probability: probability,
    country: country, league: league, kickoffAt: kickoffAt,
    bookmaker: bookmaker, chosenMarket: newMarket,
    aiPrimaryMarket: aiPrimaryMarket,
    aiPrimaryProbability: aiPrimaryProbability,
    verifiedHomeGoals: verifiedHomeGoals,
    verifiedAwayGoals: verifiedAwayGoals, scoreVerifiedAt: scoreVerifiedAt,
  );

  PersonalSelection withVerifiedScore(PersonalVerifiedScore score) =>
      PersonalSelection(
    fixtureId: fixtureId, match: match, market: market, source: source,
    capturedAt: capturedAt, odds: odds, probability: probability,
    country: country, league: league, kickoffAt: kickoffAt,
    bookmaker: bookmaker, chosenMarket: chosenMarket,
    aiPrimaryMarket: aiPrimaryMarket,
    aiPrimaryProbability: aiPrimaryProbability,
    verifiedHomeGoals: score.homeGoals,
    verifiedAwayGoals: score.awayGoals, scoreVerifiedAt: score.verifiedAt,
  );

  Map<String, dynamic> toJson() => {
    'fixtureId': fixtureId, 'match': match, 'market': market,
    'source': source, 'odds': odds, 'probability': probability,
    if (country != null) 'country': country,
    if (league != null) 'league': league,
    if (kickoffAt != null) 'kickoffAt': kickoffAt!.toUtc().toIso8601String(),
    if (bookmaker != null) 'bookmaker': bookmaker,
    if (chosenMarket != null) 'chosenMarket': chosenMarket,
    if (aiPrimaryMarket != null) 'aiPrimaryMarket': aiPrimaryMarket,
    if (aiPrimaryProbability != null)
      'aiPrimaryProbability': aiPrimaryProbability,
    if (verifiedHomeGoals != null) 'verifiedHomeGoals': verifiedHomeGoals,
    if (verifiedAwayGoals != null) 'verifiedAwayGoals': verifiedAwayGoals,
    if (scoreVerifiedAt != null)
      'scoreVerifiedAt': scoreVerifiedAt!.toUtc().toIso8601String(),
    'capturedAt': capturedAt.toIso8601String(),
  };
  factory PersonalSelection.fromJson(Map<String, dynamic> json) =>
      PersonalSelection(
        fixtureId: json['fixtureId'] as String,
        match: json['match'] as String,
        market: json['market'] as String,
        source: json['source'] as String,
        odds: (json['odds'] as num?)?.toDouble(),
        probability: (json['probability'] as num?)?.toDouble(),
        country: json['country'] is String ? json['country'] as String : null,
        league: json['league'] is String ? json['league'] as String : null,
        kickoffAt: DateTime.tryParse(json['kickoffAt']?.toString() ?? ''),
        bookmaker: json['bookmaker'] is String
            ? json['bookmaker'] as String : null,
        chosenMarket: json['chosenMarket'] is String
            ? json['chosenMarket'] as String : null,
        aiPrimaryMarket: json['aiPrimaryMarket'] is String
            ? json['aiPrimaryMarket'] as String : null,
        aiPrimaryProbability: (json['aiPrimaryProbability'] as num?)?.toDouble(),
        verifiedHomeGoals: json['verifiedHomeGoals'] is int
            ? json['verifiedHomeGoals'] as int : null,
        verifiedAwayGoals: json['verifiedAwayGoals'] is int
            ? json['verifiedAwayGoals'] as int : null,
        scoreVerifiedAt: DateTime.tryParse(
            json['scoreVerifiedAt']?.toString() ?? ''),
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );
}

class PersonalVerifiedScore {
  final int homeGoals;
  final int awayGoals;
  final DateTime verifiedAt;

  const PersonalVerifiedScore({
    required this.homeGoals,
    required this.awayGoals,
    required this.verifiedAt,
  });
}
