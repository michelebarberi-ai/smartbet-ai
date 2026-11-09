import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_coupon_probability_policy.dart';

void main() {
  test('B45 P4: il recupero al 55% non supera un limite esplicito al 65%', () {
    expect(
      GoalVdLineCouponProbabilityPolicy.accepts(
        probability: 55,
        minimumPercent: 65,
      ),
      isFalse,
    );
    expect(
      GoalVdLineCouponProbabilityPolicy.accepts(
        probability: 65,
        minimumPercent: 65,
      ),
      isTrue,
    );
  });

  test('B45 P4: calibrazione sotto la soglia viene esclusa', () {
    const initialProbability = 77;
    const calibratedProbability = 62;
    expect(
      GoalVdLineCouponProbabilityPolicy.accepts(
        probability: initialProbability,
        minimumPercent: 65,
      ),
      isTrue,
    );
    expect(
      GoalVdLineCouponProbabilityPolicy.accepts(
        probability: calibratedProbability,
        minimumPercent: 65,
      ),
      isFalse,
    );
  });

  test('B45 P4: filtro finale protegge CORE e tutte le varianti', () {
    final picks = [
      (fixtureId: 101, probability: 82),
      (fixtureId: 102, probability: 60),
      (fixtureId: 103, probability: 65),
      (fixtureId: 104, probability: 13),
      (fixtureId: 105, probability: 75),
    ];
    final safe = GoalVdLineCouponProbabilityPolicy.filter(
      picks,
      probabilityOf: (pick) => pick.probability,
      minimumPercent: 65,
    );
    expect(safe.map((p) => p.fixtureId), [101, 103, 105]);
  });

  test('B45 P4: Standard non aggiunge eventi a probabilità nulla', () {
    final picks = [0, 13, 55, 65, 101];
    final safe = GoalVdLineCouponProbabilityPolicy.filter(
      picks,
      probabilityOf: (p) => p,
      minimumPercent: 0,
    );
    expect(safe, [13, 55, 65]);
  });

  test('B45 P4: limite al 75% e configurazioni non valide', () {
    expect(
      GoalVdLineCouponProbabilityPolicy.filter(
        [74, 75, 100],
        probabilityOf: (p) => p,
        minimumPercent: 75,
      ),
      [75, 100],
    );
    expect(
      () => GoalVdLineCouponProbabilityPolicy.accepts(
        probability: 70,
        minimumPercent: 110,
      ),
      throwsRangeError,
    );
  });
}
