import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/smartbet_coupon_service.dart';

void main() {
  test('La quota minima delle schedine e 1.20', () {
    expect(SmartBetCouponService.minimumOdd, 1.20);
  });

  test('Premium, Bilanciata e Value gestiscono zero partite', () async {
    final service = SmartBetCouponService();

    final result = await service.buildCouponSet(matches: []);

    expect(result.premium.hasCoupon, isFalse);
    expect(result.balanced.hasCoupon, isFalse);
    expect(result.value.hasCoupon, isFalse);

    expect(result.availableProfiles, 0);
    expect(result.hasAnyCoupon, isFalse);
  });
}
