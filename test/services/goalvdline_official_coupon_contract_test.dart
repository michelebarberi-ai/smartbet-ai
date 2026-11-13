import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_model.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_official_coupon_contract.dart';
import 'package:smartbet_ai_new/services/smartbet_coupon_service.dart';
import 'package:smartbet_ai_new/services/smartbet_sports_market_selector.dart';

// Verifica la corrispondenza con gli handicap creati dal motore ufficiale.
void _verifyEuropeanHandicapMarketFamily() {
  for (final market in <String>[
    'HCP EURO CASA -1 1',
    'HCP EURO CASA +2 X',
    'HCP EURO CASA 0 2',
  ]) {
    expect(
      GoalVdLineOfficialCouponContract.marketFamily(market),
      'HANDICAP_EUROPEAN',
    );
  }
  for (final market in <String>[
    'HCP EURO CASA +6 1',
    'HCP EURO CASA -1 1 EXTRA',
    'HCP EURO CASA +1 1X',
  ]) {
    expect(GoalVdLineOfficialCouponContract.marketFamily(market), isNull);
  }
}

final now = DateTime.utc(2026, 11, 9, 8, 15);

AnalysisResult analysis() => const AnalysisResult(
  smartScore: 82,
  homeProbability: 67,
  drawProbability: 21,
  awayProbability: 12,
  prediction: '1',
  valueBet: '',
  risk: 'Basso',
  explanation: '',
);

MatchModel fixture(
  int id, {
  String date = '2026-11-09T20:30:00+01:00',
  String status = 'NS',
}) => MatchModel(
  fixtureId: id,
  homeTeamId: id * 2,
  awayTeamId: id * 2 + 1,
  homeTeam: 'Casa',
  awayTeam: 'Ospite',
  league: 'Test',
  leagueId: 1,
  country: 'Italia',
  countryCode: 'IT',
  date: date,
  statusShort: status,
  leagueType: 'domestic',
  isEuropeanCup: false,
  isFriendly: false,
  isNational: false,
  aiWeight: 0.75,
  smartScore: 82,
  homeWin: 67,
  draw: 21,
  awayWin: 12,
  valueBet: '',
  odd: 1.9,
);

SmartBetCouponSelection pick(
  int id,
  String market,
  int probability, {
  double odd = 1.6,
  String? date,
  int? effective,
}) => SmartBetCouponSelection(
  match: fixture(id, date: date ?? '2026-11-09T20:30:00+01:00'),
  analysis: analysis(),
  sportsPick: SmartBetSportsMarketPick(
    market: market,
    probability: probability,
    odd: odd,
  ),
  sportsBookmaker: 'Sisal',
  calibratedProbabilityPercent: effective,
);

SmartBetCouponResult coupon(List<SmartBetCouponSelection> selections) =>
    SmartBetCouponResult(
      selections: selections,
      analyzedMatches: selections.length,
      validCandidates: selections.length,
      rejectedMatches: 0,
      totalOdd: 1,
      averageSmartScore: 82,
      estimatedCombinedProbability: 0.45,
      riskLevel: 'Basso',
      recommendedStakePercent: 1,
      message: 'ok',
    );

GoalVdLineAutoCouponPreferences prefs({
  String market = 'MULTI',
  int minimum = 65,
  int events = 3,
}) => GoalVdLineAutoCouponPreferences(
  requested: true,
  market: market,
  events: events,
  minimumMarketProbability: minimum,
);

void main() {
  test('B47: esporta quota da un altro bookmaker reale con fonte', () {
    final selection = SmartBetCouponSelection(
      match: fixture(300), analysis: analysis(),
      sportsPick: const SmartBetSportsMarketPick(
        market: '1', probability: 80, odd: 1.60,
      ),
      sportsBookmaker: 'Altro Bookmaker',
    );
    final result = GoalVdLineOfficialCouponContract.serialize(
      coupon: coupon([selection, pick(301, '1', 70), pick(302, '1', 70)]),
      preferences: prefs(), now: now,
    );
    expect(result, isNotNull);
    final events = result!['events'] as List;
    expect((events.first as Map)['bookmaker'], 'Altro Bookmaker');
    expect((events.first as Map)['odds'], 1.60);
  });

  test('B47: quota 1.20 e bookmaker non attribuito non esportabili', () {
    final unknown = SmartBetCouponSelection(
      match: fixture(800), analysis: analysis(),
      sportsPick: const SmartBetSportsMarketPick(
        market: '1', probability: 80, odd: 1.50,
      ),
      sportsBookmaker: null,
    );
    expect(GoalVdLineOfficialCouponContract.serialize(
      coupon: coupon([unknown,pick(801,'1',75),pick(802,'1',75)]),
      preferences: prefs(),now:now,
    ),isNull);
    expect(GoalVdLineOfficialCouponContract.serialize(
      coupon: coupon([
        pick(803,'1',85,odd:1.20),pick(804,'1',75),pick(805,'1',75),
      ]),preferences:prefs(),now:now,
    ),isNull);
    expect(GoalVdLineOfficialCouponContract.serialize(
      coupon: coupon([
        pick(803,'1',85,odd:1.21),pick(804,'1',75),pick(805,'1',75),
      ]),preferences:prefs(),now:now,
    ),isNotNull);
    expect(GoalVdLineOfficialCouponContract.marketFamily('GOAL O OVER 2.5'),'OR');
    expect(GoalVdLineOfficialCouponContract.marketFamily('X O UNDER 3.5'),'OR');
  });

  test('P20: tre schedine con stessi 3 eventi, mercati reali diversi', () {
    final set = SmartBetCouponSet(
      premium: coupon([pick(1, 'UNDER 2.5', 70)]),
      balanced: coupon([pick(1, 'GOAL', 69), pick(2, 'OVER 2.5', 71)]),
      value: coupon([
        pick(1, 'OVER 1.5', 75),
        pick(2, 'GOAL', 74),
        pick(3, '1', 82),
      ]),
    );
    final preferences = prefs();
    final threePreferences = preferences.copyWith(
      systemMode: GoalVdLineAutoCouponPreferences.threeSameFixtures,
    );
    final result = GoalVdLineOfficialCouponContract.serializeThreeSet(
      coupons: set,
      preferences: threePreferences,
      now: now,
    );
    expect(result, isNotNull);
    final variants = result!['coupons'] as List;
    expect(variants.length, 3);
    final ids = (result['events'] as List).map((e) => e['fixtureId']).toList();
    final signatures = <String>{};
    for (final couponResult in variants) {
      final selections = couponResult['events'] as List;
      expect(selections.map((e) => e['fixtureId']).toList(), ids);
      signatures.add(selections.map((e) => e['market']).join('|'));
    }
    expect(signatures.length, 3);
  });

  test('P20.4: richiede la finestra corretta per tre giornate', () {
    final set = SmartBetCouponSet(
      premium: coupon([]), balanced: coupon([]),
      value: coupon([
        pick(1, 'OVER 1.5', 76),
        pick(2, 'OVER 1.5', 76,
            date: '2026-11-10T20:30:00+01:00'),
        pick(3, 'OVER 1.5', 76,
            date: '2026-11-11T20:30:00+01:00'),
      ]),
      verifiedMarketAlternatives: [
        pick(1, 'GOAL', 70),
        pick(2, 'GOAL', 70, date: '2026-11-10T20:30:00+01:00'),
        pick(3, 'GOAL', 70, date: '2026-11-11T20:30:00+01:00'),
      ],
    );
    final mode = prefs().copyWith(
      systemMode: GoalVdLineAutoCouponPreferences.threeSameFixtures,
      windowDays: 3,
    );
    final result = GoalVdLineOfficialCouponContract.serializeThreeSet(
      coupons: set, preferences: mode, now: now,
    );
    expect(result, isNotNull);
    expect(result!['windowDays'], 3);
    expect((result['coupons'] as List).length, 3);
    expect(GoalVdLineOfficialCouponContract.serializeThreeSet(
      coupons: set, preferences: mode.copyWith(windowDays: 2), now: now,
    ), isNull);
  });

  test('P20: richiede mercato alternativo reale e non crea tre copie', () {
    final set = SmartBetCouponSet(
      premium: coupon([]),
      balanced: coupon([]),
      value: coupon([
        pick(1, 'OVER 1.5', 76),
        pick(2, 'GOAL', 77),
        pick(3, '1', 78),
      ]),
    );
    expect(
      GoalVdLineOfficialCouponContract.serializeThreeSet(
        coupons: set,
        preferences: prefs(),
        now: now,
      ),
      isNull,
    );
  });

  test('P20: esporta 15 partite solo se selezioni ufficiali sufficienti', () {
    final set = SmartBetCouponSet(
      premium: coupon([pick(1, 'UNDER 2.5', 70)]),
      balanced: coupon([pick(1, 'GOAL', 70), pick(2, 'OVER 2.5', 70)]),
      value: coupon([for (var i = 1; i <= 15; i++) pick(i, 'OVER 1.5', 75)]),
    );
    final result = GoalVdLineOfficialCouponContract.serializeThreeSet(
      coupons: set,
      preferences: prefs(events: 15),
      now: now,
    );
    expect(result, isNotNull);
    expect((result!['events'] as List).length, 15);
    expect((result['coupons'] as List).length, 3);
  });

  test('exports real European handicap selections from Flutter', () {
    final result = GoalVdLineOfficialCouponContract.serialize(
      coupon: coupon([
        pick(201, 'HCP EURO CASA -1 1', 75),
        pick(202, 'HCP EURO CASA +2 X', 70),
        pick(203, 'HCP EURO CASA 0 2', 69),
      ]),
      preferences: prefs(),
      now: now,
    );
    expect(result, isNotNull);
    expect((result!['events'] as List).length, 3);
    expect((result['events'] as List).first['market'], 'HCP EURO CASA -1 1');
    expect(
      GoalVdLineOfficialCouponContract.serialize(
        coupon: coupon([
          pick(201, 'HCP EURO CASA -1 1', 75),
          pick(202, 'HCP EURO CASA +2 X', 70),
          pick(203, 'HCP EURO CASA 0 2', 69),
        ]),
        preferences: prefs(market: '1X2'),
        now: now,
      ),
      isNull,
    );
  });

  test('European handicap from official engine is mapped', () {
    _verifyEuropeanHandicapMarketFamily();
  });
  test('Flutter market classification matches the Node server categories', () {
    expect(
      GoalVdLineOfficialCouponContract.marketFamily('OVER 2.5'),
      'OVER_UNDER',
    );
    expect(
      GoalVdLineOfficialCouponContract.marketFamily('UNDER 1.5'),
      'OVER_UNDER',
    );
    expect(
      GoalVdLineOfficialCouponContract.marketFamily('GOAL'),
      'GOAL_NOGOAL',
    );
    expect(
      GoalVdLineOfficialCouponContract.marketFamily('NO GOAL'),
      'GOAL_NOGOAL',
    );
    expect(GoalVdLineOfficialCouponContract.marketFamily('1'), '1X2');
    expect(GoalVdLineOfficialCouponContract.marketFamily('X'), '1X2');
    expect(GoalVdLineOfficialCouponContract.marketFamily('1X'), null);
  });

  test('exports actual market probability and odds, never SmartScore', () {
    final data = GoalVdLineOfficialCouponContract.serialize(
      coupon: coupon([
        pick(21, 'GOAL', 80),
        pick(22, 'NO GOAL', 70),
        pick(23, 'GOAL', 68),
      ]),
      preferences: prefs(market: 'GOAL_NOGOAL'),
      now: now,
    );
    expect(data, isNotNull);
    final events = data!['events'] as List<Map<String, Object>>;
    expect(events.length, 3);
    expect(events[0]['marketProbability'], 80);
    expect(events[0]['market'], 'GOAL');
    expect(events[0]['odds'], 1.6);
    expect(events[0]['kickoffAt'], '2026-11-09T19:30:00.000Z');
    expect(events[0].containsKey('smartScore'), false);
  });

  test('fails closed if filters leave insufficient real selections', () {
    expect(
      GoalVdLineOfficialCouponContract.serialize(
        coupon: coupon([
          pick(21, 'GOAL', 80),
          pick(22, 'GOAL', 64),
          pick(23, 'GOAL', 88),
        ]),
        preferences: prefs(),
        now: now,
      ),
      isNull,
    );
    expect(
      GoalVdLineOfficialCouponContract.serialize(
        coupon: coupon([
          pick(21, 'GOAL', 80),
          pick(21, 'GOAL', 70),
          pick(23, 'GOAL', 88),
        ]),
        preferences: prefs(),
        now: now,
      ),
      isNull,
    );
    expect(
      GoalVdLineOfficialCouponContract.serialize(
        coupon: coupon([
          pick(21, 'GOAL', 80, odd: double.nan),
          pick(22, 'GOAL', 70),
          pick(23, 'GOAL', 88),
        ]),
        preferences: prefs(),
        now: now,
      ),
      isNull,
    );
  });

  test('enforces single-family categories after ranking', () {
    final result = GoalVdLineOfficialCouponContract.serialize(
      coupon: coupon([
        pick(1, 'OVER 2.5', 70),
        pick(2, 'GOAL', 76),
        pick(3, 'UNDER 2.5', 78),
        pick(4, 'OVER 1.5', 66),
      ]),
      preferences: prefs(market: 'OVER_UNDER'),
      now: now,
    );
    expect((result!['events'] as List).length, 3);
    expect(
      (result['events'] as List<Map<String, Object>>).map(
        (e) => e['fixtureId'],
      ),
      [1, 3, 4],
    );
  });

  test('excludes games already begun or outside Rome day', () {
    final selected = coupon([
      pick(1, 'GOAL', 80, date: '2026-11-09T07:00:00Z'),
      pick(2, 'GOAL', 80, date: '2026-11-10T00:30:00+01:00'),
      pick(3, 'GOAL', 80),
    ]);
    expect(
      GoalVdLineOfficialCouponContract.serialize(
        coupon: selected,
        preferences: prefs(),
        now: now,
      ),
      isNull,
    );
  });

  test('falls back only to another complete official strategy', () {
    final strategies = SmartBetCouponSet(
      premium: coupon([pick(1, 'GOAL', 82), pick(2, 'GOAL', 75)]),
      balanced: coupon([
        pick(3, 'GOAL', 83),
        pick(4, 'GOAL', 72),
        pick(5, 'GOAL', 66),
      ]),
      value: coupon([
        pick(6, 'GOAL', 80),
        pick(7, 'GOAL', 80),
        pick(8, 'GOAL', 80),
      ]),
    );
    final result = GoalVdLineOfficialCouponContract.serializeSet(
      coupons: strategies,
      preferences: prefs(),
      now: now,
    );
    expect(
      (result!['events'] as List<Map<String, Object>>).map(
        (e) => e['fixtureId'],
      ),
      [3, 4, 5],
    );
  });

  test('post-calibration market probability is the value exported', () {
    final selected = coupon([
      pick(1, '1', 90, effective: 64),
      pick(2, 'X', 70),
      pick(3, '2', 75),
      pick(4, '1', 80),
    ]);
    final result = GoalVdLineOfficialCouponContract.serialize(
      coupon: selected,
      preferences: prefs(market: '1X2'),
      now: now,
    );
    expect(
      (result!['events'] as List<Map<String, Object>>).map(
        (e) => e['fixtureId'],
      ),
      [2, 3, 4],
    );
  });

  test('P20.1: alternative della stessa analisi sbloccano tre schedine', () {
    // I tre profili espongono soltanto un mercato per partita: P20 era null.
    final base = [
      pick(1, 'OVER 1.5', 76),
      pick(2, 'OVER 1.5', 77),
      pick(3, '1', 91),
    ];
    final set = SmartBetCouponSet(
      premium: coupon([]),
      balanced: coupon([]),
      value: coupon(base),
      verifiedMarketAlternatives: [
        pick(1, 'GOAL', 70),
        pick(2, 'UNDER 2.5', 72),
      ],
    );
    final data = GoalVdLineOfficialCouponContract.serializeThreeSet(
      coupons: set,
      preferences: prefs().copyWith(
        systemMode: GoalVdLineAutoCouponPreferences.threeSameFixtures,
      ),
      now: now,
    );
    expect(data, isNotNull);
    final slips = data!['coupons'] as List;
    expect(slips.length, 3);
    final signatures = <String>{};
    for (final slip in slips) {
      final selections = (slip as Map)['events'] as List;
      expect(selections.map((event) => event['fixtureId']).toList(), [3, 2, 1]);
      signatures.add(selections.map((event) => event['market']).join('|'));
    }
    expect(signatures.length, 3);
    // La selezione piu' solida non cambia.
    for (final slip in slips) {
      expect(((slip as Map)['events'] as List).first['market'], '1');
    }
  });

  test('P20.1: cerca fixture con alternative oltre le prime tre', () {
    final set = SmartBetCouponSet(
      premium: coupon([]),
      balanced: coupon([]),
      value: coupon([
        pick(1, '1', 94),
        pick(2, '1', 90),
        pick(3, '1', 88),
        pick(4, 'OVER 1.5', 76),
        pick(5, 'OVER 1.5', 75),
      ]),
      verifiedMarketAlternatives: [
        pick(4, 'GOAL', 70),
        pick(5, 'UNDER 2.5', 69),
      ],
    );
    final data = GoalVdLineOfficialCouponContract.serializeThreeSet(
      coupons: set,
      preferences: prefs().copyWith(
        systemMode: GoalVdLineAutoCouponPreferences.threeSameFixtures,
      ),
      now: now,
    );
    expect(data, isNotNull);
    final ids = (data!['events'] as List).map((e) => e['fixtureId']).toList();
    expect(ids, [1, 4, 5]);
  });

  test('P20.1: alternativa calibrata sotto soglia non viene esportata', () {
    final set = SmartBetCouponSet(
      premium: coupon([]),
      balanced: coupon([]),
      value: coupon([
        pick(1, 'OVER 1.5', 76),
        pick(2, 'OVER 1.5', 77),
        pick(3, '1', 91),
      ]),
      verifiedMarketAlternatives: [
        pick(1, 'GOAL', 70, effective: 64),
        pick(2, 'UNDER 2.5', 72),
      ],
    );
    expect(
      GoalVdLineOfficialCouponContract.serializeThreeSet(
        coupons: set,
        preferences: prefs().copyWith(
          systemMode: GoalVdLineAutoCouponPreferences.threeSameFixtures,
        ),
        now: now,
      ),
      isNull,
    );
  });

  test('P20.1: alternative non cambiano la singola schedina storica', () {
    final set = SmartBetCouponSet(
      premium: coupon([]),
      balanced: coupon([]),
      value: coupon([
        pick(1, 'OVER 1.5', 76),
        pick(2, 'OVER 1.5', 77),
        pick(3, '1', 91),
      ]),
      verifiedMarketAlternatives: [pick(1, 'GOAL', 70)],
    );
    final data = GoalVdLineOfficialCouponContract.serializeSet(
      coupons: set,
      preferences: prefs(),
      now: now,
    );
    expect(data, isNotNull);
    expect((data!['events'] as List).map((e) => e['market']).toList(), [
      'OVER 1.5',
      'OVER 1.5',
      '1',
    ]);
  });
}
