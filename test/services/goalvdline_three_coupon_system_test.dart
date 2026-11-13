import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_three_coupon_system.dart';

GoalVdLineSystemSelection pick(
  int id,
  String market,
  int probability, {
  double odd = 1.8,
}) => GoalVdLineSystemSelection(
  fixtureId: id,
  market: market,
  probability: probability,
  odd: odd,
  bookmaker: 'Test',
);

void main() {
  test('tre schedine diverse mantengono le stesse partite', () {
    final result = GoalVdLineThreeCouponSystem.create(
      original: [pick(1, '1X', 77), pick(2, 'OVER 1.5', 79), pick(3, '1', 92)],
      alternatives: {
        1: [pick(1, 'GOAL', 70), pick(1, 'OVER 2.5', 68)],
        2: [pick(2, 'GOAL', 73)],
        3: [pick(3, 'X', 66)],
      },
    );
    expect(result, isNotNull);
    expect(result!.length, 3);
    for (final coupon in result) {
      expect(coupon.map((e) => e.fixtureId).toList(), [1, 2, 3]);
      expect(coupon.every((e) => e.probability >= 65), isTrue);
      expect(coupon[2].market, '1');
    }
    expect(result[0][0].market, '1X');
    expect(result[1][0].market, 'GOAL');
    expect(result[2][0].market, 'OVER 2.5');
  });

  test('due sole alternative in due partite bastano per tre varianti', () {
    final result = GoalVdLineThreeCouponSystem.create(
      original: [pick(1, '1X', 77), pick(2, 'OVER 1.5', 79), pick(3, '1', 92)],
      alternatives: {
        1: [pick(1, 'GOAL', 70)],
        2: [pick(2, 'X2', 68)],
      },
    );
    expect(result, isNotNull);
    expect(result![1][0].market, 'GOAL');
    expect(result[2][0].market, '1X');
    expect(result[2][1].market, 'X2');
  });

  test('nessuna forzatura se non ci sono tre varianti credibili', () {
    expect(
      GoalVdLineThreeCouponSystem.create(
        original: [pick(1, '1X', 77), pick(2, '1', 95), pick(3, '2', 94)],
        alternatives: {
          1: [pick(1, 'GOAL', 66)],
        },
      ),
      isNull,
    );
  });

  test('mercati sotto 65, quote errate e duplicati vengono scartati', () {
    final original = [pick(1, '1X', 77), pick(2, '2', 80), pick(3, '1', 90)];
    expect(
      GoalVdLineThreeCouponSystem.create(
        original: original,
        alternatives: {
          1: [pick(1, 'GOAL', 64), pick(1, 'X', 70, odd: 0)],
        },
      ),
      isNull,
    );
    expect(
      GoalVdLineThreeCouponSystem.create(
        original: [original[0], original[0], original[2]],
        alternatives: const {},
      ),
      isNull,
    );
  });

  test('B47: quota maggiore di 1.21 per CORE e alternative', () {
    final coupons = GoalVdLineThreeCouponSystem.create(
      original: [
        pick(1, '1X', 77, odd: 1.21),
        pick(2, 'OVER 1.5', 90, odd: 1.21),
        pick(3, '1', 92, odd: 1.21),
      ],
      alternatives: {
        1: [
          pick(1, 'GOAL', 70, odd: 1.21),
          pick(1, 'OVER 2.5', 68, odd: 1.21),
        ],
      },
    );
    expect(coupons, isNotNull);
    expect(coupons!.length, 3);
    expect(coupons.every((coupon) =>
        coupon.every((selection) => selection.odd > 1.20)), isTrue);
    expect(coupons.every((coupon) =>
        coupon.every((selection) => selection.probability >= 65)), isTrue);
  });

  test('B45: quote sotto 1.20 e probabilita 7-13 non salvano un sistema', () {
    final original = [
      pick(1, '1X', 77, odd: 1.21),
      pick(2, 'OVER 1.5', 90, odd: 1.21),
      pick(3, '1', 92, odd: 1.21),
    ];
    final invalidAlternatives = {
      1: [
        pick(1, 'GOAL', 70, odd: 1.19),
        pick(1, '2', 13, odd: 20.00),
        pick(1, 'X', 7, odd: 30.00),
      ],
    };
    expect(GoalVdLineThreeCouponSystem.create(
      original: original, alternatives: invalidAlternatives,
    ), isNull);
    expect(GoalVdLineThreeCouponSystem.create(
      original: [pick(1, '1X', 77, odd: 1.19), original[1], original[2]],
      alternatives: {1: [pick(1, 'GOAL', 70, odd: 1.21),
        pick(1, 'OVER 2.5', 68, odd: 1.21)]},
    ), isNull);
  });

  test('accetta da 3 a 15 eventi ma non 2 o 16', () {
    for (final n in [2, 16]) {
      expect(
        GoalVdLineThreeCouponSystem.create(
          original: [for (var i = 1; i <= n; i++) pick(i, '1X', 75)],
          alternatives: const {},
        ),
        isNull,
      );
    }
  });
}
