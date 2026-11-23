import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/personal_coupon_store.dart';
import 'package:smartbet_ai_new/services/personal_coupon_review_service.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

final cutoff = DateTime.utc(2026, 11, 23, 11);

PersonalSelection pick({
  String fixture = '100',
  String market = 'UNDER 4.5',
  String? chosen,
  DateTime? kickoff,
  int? home,
  int? away,
  DateTime? verified,
}) => PersonalSelection(
  fixtureId: fixture, match: 'Home - Away', market: market,
  source: 'Crea Schedina', capturedAt: DateTime.utc(2026, 11, 21),
  odds: 1.25, probability: 86,
  country: 'Belgio', league: 'Jupiler Pro League',
  kickoffAt: kickoff,
  chosenMarket: chosen, verifiedHomeGoals: home,
  verifiedAwayGoals: away, scoreVerifiedAt: verified,
  aiPrimaryMarket: '1X O UNDER 3.5',
  aiPrimaryProbability: 94,
);

void main() {
  const svc = PersonalCouponReviewService();

  test('B78: original market and top AI proposal survive personal edit',
      () {
    final original = pick();
    final edited = original.withChosenMarket('X2');
    expect(edited.market, 'UNDER 4.5');
    expect(edited.currentMarket, 'X2');
    expect(edited.editedByUser, isTrue);
    expect(edited.currentOdds, isNull);
    expect(edited.currentProbability, isNull);
    expect(edited.aiPrimaryMarket, '1X O UNDER 3.5');
    final restored = PersonalSelection.fromJson(edited.toJson());
    expect(restored.currentMarket, 'X2');
    expect(restored.market, 'UNDER 4.5');
    expect(restored.aiPrimaryProbability, 94);
    expect(restored.withChosenMarket('UNDER 4.5').editedByUser, isFalse);
  });

  test('B78: old B77 coupons have no fabricated AI or settled fields',
      () {
    final restored = PersonalSelection.fromJson({
      'fixtureId': '100', 'match': 'Home - Away',
      'market': 'UNDER 4.5', 'source': 'Crea Schedina',
      'capturedAt': '2026-11-21T00:00:00.000Z',
    });
    expect(restored.editedByUser, isFalse);
    expect(restored.aiPrimaryMarket, isNull);
    expect(restored.verifiedHomeGoals, isNull);
    expect(svc.review(restored, [] ).status,
      PersonalPickReviewStatus.pending);
  });

  test('B78: repeated markets count distinct slips and are not AI accuracy',
      () {
    final p = pick();
    final a = PersonalCoupon(id: 'a', name: 'A', selections: [p, p]);
    final b = PersonalCoupon(id: 'b', name: 'B', selections: [p]);
    final c = PersonalCoupon(id: 'c', name: 'C',
      selections: [pick(market: 'OVER 2.5')]);
    final counts = svc.repeatedSelections([a, b, c]);
    expect(svc.repeatedInCoupons(p, counts), 2);
    expect(svc.repeatedInCoupons(c.selections.first, counts), 1);
  });

  test('B78: valid final scores settle markets but never unsupported ones',
      () {
    final outcome = PersonalVerifiedScore(
      homeGoals: 2, awayGoals: 1, verifiedAt: cutoff);
    expect(svc.review(pick().withVerifiedScore(outcome), []).status,
      PersonalPickReviewStatus.correct);
    expect(svc.review(pick(chosen: 'UNDER 2.5')
        .withVerifiedScore(outcome), []).status,
      PersonalPickReviewStatus.wrong);
    expect(svc.review(pick(market: 'Goal O Under')
        .withVerifiedScore(outcome), []).status,
      PersonalPickReviewStatus.unsupported);
    expect(svc.review(pick(), []).status,
      PersonalPickReviewStatus.pending);
  });

  test('B78: finished fixture queried once only after four hours',
      () async {
    var calls = 0;
    final result = await svc.fetchFinished(
      now: cutoff,
      history: const <SmartBetAnalysisRecord>[],
      selections: [
        pick(kickoff: cutoff.subtract(const Duration(hours: 8))),
        pick(kickoff: cutoff.subtract(const Duration(hours: 8))),
        pick(fixture: '101',
          kickoff: cutoff.subtract(const Duration(hours: 2))),
        pick(fixture: '102'),
      ],
      fetchByDate: (date) async {
        calls++;
        return [
          {
            'fixture': {'id': 100, 'status': {'short': 'FT'}},
            'goals': {'home': 2, 'away': 1},
          },
          {
            'fixture': {'id': 101, 'status': {'short': 'FT'}},
            'goals': {'home': 2, 'away': 1},
          },
        ];
      },
    );
    expect(calls, 1);
    expect(result.daysQueried, 1);
    expect(result.fixturesEligible, 1);
    expect(result.missingKickoff, 1);
    expect(result.scores['100']?.homeGoals, 2);
    expect(result.scores.containsKey('101'), isFalse);
  });

  test('B78: extra time settles on fulltime, not extra time goals',
      () async {
    final report = await svc.fetchFinished(
      now: cutoff,
      history: const <SmartBetAnalysisRecord>[],
      selections: [pick(
        kickoff: cutoff.subtract(const Duration(hours: 12)),
      )],
      fetchByDate: (_) async => [
        {
          'fixture': {'id': 100, 'status': {'short': 'AET'}},
          'score': {'fulltime': {'home': 1, 'away': 1}},
          'goals': {'home': 2, 'away': 1},
        },
      ],
    );
    expect(report.scores['100']?.homeGoals, 1);
    expect(report.scores['100']?.awayGoals, 1);
  });

  test('B78: postponed, missing or awarded fixtures remain unverified',
      () async {
    final report = await svc.fetchFinished(
      now: cutoff,
      history: const <SmartBetAnalysisRecord>[],
      selections: [pick(
        kickoff: cutoff.subtract(const Duration(hours: 12)),
      )],
      fetchByDate: (_) async => [
        {
          'fixture': {'id': 100, 'status': {'short': 'AWD'}},
          'goals': {'home': 3, 'away': 0},
        },
      ],
    );
    expect(report.scores, isEmpty);
    expect(report.fixturesNotFinal, 1);
  });

  test('B78: settled coupon summary counts distinct states', () {
    final done = PersonalVerifiedScore(
      homeGoals: 2, awayGoals: 1, verifiedAt: cutoff);
    final slip = PersonalCoupon(
      id: 'A', name: 'A', selections: [
        pick().withVerifiedScore(done),
        pick(fixture: '101', market: 'X').withVerifiedScore(done),
        pick(fixture: '102', market: 'Marcatore X').withVerifiedScore(done),
        pick(fixture: '103'),
      ],
    );
    final summary = svc.summarize(slip, []);
    expect(summary.correct, 1);
    expect(summary.wrong, 1);
    expect(summary.unsupported, 1);
    expect(summary.pending, 1);
    expect(summary.verified, 2);
  });
}
