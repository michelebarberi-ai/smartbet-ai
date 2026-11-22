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
  final DateTime capturedAt;
  const PersonalSelection({required this.fixtureId, required this.match,
    required this.market, required this.source, required this.capturedAt,
    this.odds, this.probability, this.country, this.league, this.kickoffAt,
    this.bookmaker});

  Map<String, dynamic> toJson() => {
    'fixtureId': fixtureId, 'match': match, 'market': market,
    'source': source, 'odds': odds, 'probability': probability,
    if (country != null) 'country': country,
    if (league != null) 'league': league,
    if (kickoffAt != null) 'kickoffAt': kickoffAt!.toUtc().toIso8601String(),
    if (bookmaker != null) 'bookmaker': bookmaker,
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
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );
}
