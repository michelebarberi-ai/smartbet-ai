import 'goalvdline_auto_coupon_preferences.dart';
import 'goalvdline_rome_day_window.dart';
import 'goalvdline_three_coupon_system.dart';
import 'smartbet_coupon_service.dart';
import 'goalvdline_quote_policy.dart';

/// P16: exports ONLY the official Flutter selections. This is not a new
/// prediction/ranking model, and does not send anything to the server.
/// An independent, headless execution of the official engine is still needed.
class GoalVdLineOfficialCouponContract {
  const GoalVdLineOfficialCouponContract._();

  static String? marketFamily(String market) {
    final normalized = market
        .trim()
        .toUpperCase()
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (RegExp(r'^(OVER|UNDER) ?\d+(\.\d+)?$').hasMatch(normalized) ||
        normalized == 'OVER_UNDER') {
      return GoalVdLineAutoCouponPreferences.overUnder;
    }
    if (const <String>{
      'GOAL',
      'NO GOAL',
      'NOGOAL',
      'BTTS YES',
      'BTTS NO',
      'GOAL_NOGOAL',
    }.contains(normalized)) {
      return GoalVdLineAutoCouponPreferences.goalNoGoal;
    }
    if (const <String>{'1', 'X', '2', '1X2'}.contains(normalized)) {
      return GoalVdLineAutoCouponPreferences.oneXTwo;
    }
    // Official European handicap candidates are selected only when quoted.
    // Accepted range and outcome match the real Flutter candidate service.
    if (RegExp(r'^HCP EURO CASA [+-]?[0-5] [1X2]$').hasMatch(normalized)) {
      return 'HANDICAP_EUROPEAN';
    }
    return null;
  }

  /// Uses the existing official profile order. If the preferred strategy has
  /// fewer than the requested events, try the other *already generated* official
  /// strategies. No predictions or markets are synthesized here.
  static Map<String, Object>? serializeSet({
    required SmartBetCouponSet coupons,
    required GoalVdLineAutoCouponPreferences preferences,
    required DateTime now,
  }) {
    for (final profile in <SmartBetCouponResult>[
      coupons.premium,
      coupons.balanced,
      coupons.value,
    ]) {
      final result = serialize(
        coupon: profile,
        preferences: preferences,
        now: now,
      );
      if (result != null) return result;
    }
    return null;
  }

  /// Validates and serializes an already-generated official coupon. Selection
  /// order is preserved; any insufficient set fails closed (null).
  /// Probabilities come from the selected market, NEVER from SmartScore.
  static Map<String, Object>? serialize({
    required SmartBetCouponResult coupon,
    required GoalVdLineAutoCouponPreferences preferences,
    required DateTime now,
  }) {
    if (!preferences.isValid || !preferences.requested) return null;
    final utcNow = now.toUtc();
    final usedFixtures = <int>{};
    final events = <Map<String, Object>>[];
    for (final selection in coupon.selections) {
      final pick = selection.sportsPick;
      if (pick == null || selection.match.fixtureId <= 0) continue;
      final family = marketFamily(pick.market);
      if (family == null ||
          (preferences.market != GoalVdLineAutoCouponPreferences.multiMarket &&
              family != preferences.market))
        continue;
      final probability = selection.effectiveProbabilityPercent;
      if (probability < preferences.minimumMarketProbability ||
          probability > 100)
        continue;
      // Every exported quote comes from the actual sports market pick.
      if (!pick.odd.isFinite || pick.odd <= 1.0) continue;
      final kickoff = DateTime.tryParse(selection.match.date)?.toUtc();
      if (kickoff == null ||
          !GoalVdLineRomeDayWindow.includes(
            kickoff: kickoff, now: utcNow, windowDays: preferences.windowDays))
        continue;
      final status = selection.match.statusShort.trim().toUpperCase();
      if (status.isNotEmpty && status != 'NS') continue;
      if (!usedFixtures.add(selection.match.fixtureId)) continue;

      events.add(<String, Object>{
        'fixtureId': selection.match.fixtureId,
        'market': pick.market,
        'marketProbability': probability,
        'kickoffAt': kickoff.toIso8601String(),
        'odds': pick.odd,
      });
      if (events.length == preferences.events) break;
    }
    if (events.length != preferences.events) return null;
    return <String, Object>{
      if (preferences.windowDays > 1) 'windowDays': preferences.windowDays,
      'events': events,
    };
  }

  /// P20: builds THREE coordinated coupons using only the selections produced
  /// by the real Flutter engine. Different profiles may supply alternative
  /// quoted markets for the same fixture; no market is invented. This may
  /// return null if insufficient unique fixtures or alternatives exist.
  static Map<String, Object>? serializeThreeSet({
    required SmartBetCouponSet coupons,
    required GoalVdLineAutoCouponPreferences preferences,
    required DateTime now,
  }) {
    if (!preferences.requested ||
        !preferences.isValid ||
        preferences.systemMode !=
            GoalVdLineAutoCouponPreferences.threeSameFixtures)
      return null;
    final utcNow = now.toUtc();
    final seen = <int, Map<String, SmartBetCouponSelection>>{};
    // I profili restano intatti. Il catalogo opzionale P20.1 contiene
    // ulteriori selezioni della STESSA analisi, non risultati sintetici.
    final officialSelections = <SmartBetCouponSelection>[
      ...coupons.value.selections,
      ...coupons.balanced.selections,
      ...coupons.premium.selections,
      ...coupons.verifiedMarketAlternatives,
    ];
    for (final selection in officialSelections) {
      final pick = selection.sportsPick;
      if (pick == null || selection.match.fixtureId <= 0) continue;
      final family = marketFamily(pick.market);
      if (family == null ||
          (preferences.market != GoalVdLineAutoCouponPreferences.multiMarket &&
              family != preferences.market)) {
        continue;
      }
      final percent = selection.effectiveProbabilityPercent;
      if (percent < preferences.minimumMarketProbability ||
          percent > 100 ||
          !pick.odd.isFinite ||
          pick.odd < GoalVdLineQuotePolicy.minimumOdd) {
        continue;
      }
      final kickoff = DateTime.tryParse(selection.match.date)?.toUtc();
      if (kickoff == null ||
          !GoalVdLineRomeDayWindow.includes(
            kickoff: kickoff, now: utcNow, windowDays: preferences.windowDays)) {
        continue;
      }
      final status = selection.match.statusShort.trim().toUpperCase();
      if (status.isNotEmpty && status != 'NS') continue;
      seen
          .putIfAbsent(selection.match.fixtureId, () => {})
          .putIfAbsent(pick.market, () => selection);
    }
    if (seen.length < preferences.events) return null;

    GoalVdLineSystemSelection convert(SmartBetCouponSelection selected) {
      final pick = selected.sportsPick!;
      return GoalVdLineSystemSelection(
        fixtureId: selected.match.fixtureId,
        market: pick.market,
        probability: selected.effectiveProbabilityPercent,
        odd: pick.odd,
        bookmaker: selected.bookmaker,
      );
    }

    // Un mercato principale per fixture, determinato dalla probabilita'
    // sportiva effettiva (non dalla quota o dall'ordine dei profili).
    final sortedOptions = <int, List<SmartBetCouponSelection>>{};
    for (final entry in seen.entries) {
      final options = entry.value.values.toList()
        ..sort((a, b) {
          final probability = b.effectiveProbabilityPercent.compareTo(
            a.effectiveProbabilityPercent,
          );
          return probability != 0
              ? probability
              : a.outcome.compareTo(b.outcome);
        });
      sortedOptions[entry.key] = options;
    }
    final rankedIds = sortedOptions.keys.toList()
      ..sort((a, b) {
        final probability = sortedOptions[b]!.first.effectiveProbabilityPercent
            .compareTo(sortedOptions[a]!.first.effectiveProbabilityPercent);
        return probability != 0 ? probability : a.compareTo(b);
      });

    // La modalita' 3 schede puo' diversificare una fixture con due
    // alternative oppure almeno due fixture con una alternativa ciascuna.
    // Le selezioni >=80% restano ferme per scelta del generatore P20.
    final flexible = <int>[];
    final doubleFlexible = <int>[];
    for (final id in rankedIds) {
      final options = sortedOptions[id]!;
      final base = options.first;
      if (base.effectiveProbabilityPercent >= 80) continue;
      final viable = options
          .skip(1)
          .where(
            (candidate) =>
                candidate.effectiveProbabilityPercent >=
                base.effectiveProbabilityPercent - 12,
          )
          .length;
      if (viable >= 1) flexible.add(id);
      if (viable >= 2) doubleFlexible.add(id);
    }

    List<List<GoalVdLineSystemSelection>>? bestVariants;
    var bestQuality = -1;
    // Riserva eventuali fixture differenziabili e riempie i posti restanti
    // con le piu' affidabili. Tutti i tentativi sono validati da P20.
    void consider(List<int> requiredIds) {
      if (requiredIds.length > preferences.events) return;
      final required = requiredIds.toSet();
      final ids = <int>[
        ...requiredIds,
        ...rankedIds
            .where((id) => !required.contains(id))
            .take(preferences.events - requiredIds.length),
      ];
      if (ids.length != preferences.events) return;
      ids.sort((a, b) => rankedIds.indexOf(a).compareTo(rankedIds.indexOf(b)));
      final primary = <GoalVdLineSystemSelection>[];
      final alternatives = <int, List<GoalVdLineSystemSelection>>{};
      for (final id in ids) {
        final options = sortedOptions[id]!;
        primary.add(convert(options.first));
        alternatives[id] = options.skip(1).map(convert).toList();
      }
      final variants = GoalVdLineThreeCouponSystem.create(
        original: primary,
        alternatives: alternatives,
        minimumProbability: preferences.minimumMarketProbability,
      );
      if (variants == null) return;
      final quality = primary.fold<int>(
        0,
        (sum, pick) => sum + pick.probability,
      );
      if (quality > bestQuality) {
        bestQuality = quality;
        bestVariants = variants;
      }
    }

    // Prova anche un solo incontro con almeno due alternative reali.
    for (final id in doubleFlexible) {
      consider([id]);
    }
    // In alternativa riserva due incontri diversi con un'alternativa.
    for (var i = 0; i < flexible.length; i++) {
      for (var j = i + 1; j < flexible.length; j++) {
        consider([flexible[i], flexible[j]]);
      }
    }
    final variants = bestVariants;
    if (variants == null) return null;

    final realSelections = seen;
    final names = ['PRINCIPALE', 'ALTERNATIVA_1', 'ALTERNATIVA_2'];
    final result = <Map<String, Object>>[];
    for (var i = 0; i < variants.length; i++) {
      final events = <Map<String, Object>>[];
      for (final candidate in variants[i]) {
        final selected = realSelections[candidate.fixtureId]?[candidate.market];
        if (selected == null || selected.sportsPick == null) return null;
        // The canonical date is sourced from the identical real fixture.
        final kickoff = DateTime.tryParse(selected.match.date)?.toUtc();
        if (kickoff == null) return null;
        events.add(<String, Object>{
          'fixtureId': candidate.fixtureId,
          'market': candidate.market,
          'marketProbability': candidate.probability,
          'kickoffAt': kickoff.toIso8601String(),
          'odds': candidate.odd,
        });
      }
      result.add(<String, Object>{'name': names[i], 'events': events});
    }
    // Redundant first coupon keeps old consumers compatible. Node validates
    // that the full three-coupon bundle is present before persisting.
    return <String, Object>{
      if (preferences.windowDays > 1) 'windowDays': preferences.windowDays,
      'events': result.first['events']!,
      'coupons': result,
    };
  }

}
