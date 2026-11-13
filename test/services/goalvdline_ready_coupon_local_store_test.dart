import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_ready_coupon_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = GoalVdLineReadyCouponLocalStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('B45 local-only: completed coupon survives a fresh store instance', () async {
    expect(await store.load(), isNull);
    const coupon = 'GOALVDLINE\\nCORE — 3 partite\\n1. Team A - Team B | 1X | 78% | quota 1.30';
    expect(await store.save(coupon), true);
    expect(await const GoalVdLineReadyCouponLocalStore().load(), coupon);
  });

  test('B45 local-only: invalid empty and oversized coupon never replace latest', () async {
    expect(await store.save('GOALVDLINE - previous'), true);
    expect(await store.save('   '), false);
    expect(await store.save(List.filled(GoalVdLineReadyCouponLocalStore.maxLength + 1, 'x').join()), false);
    expect(await store.load(), 'GOALVDLINE - previous');
  });

  test('B45 local-only: invalid stored data fails closed', () async {
    SharedPreferences.setMockInitialValues({
      GoalVdLineReadyCouponLocalStore.key: '',
    });
    expect(await store.load(), isNull);
  });
}
