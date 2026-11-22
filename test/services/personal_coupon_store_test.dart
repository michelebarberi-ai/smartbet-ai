import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/personal_coupon_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('personal coupons persist names and avoid duplicate markets', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PersonalCouponStore.instance;
    await store.initialize();
    await store.create('Weekend');
    final slip = store.coupons.last;
    expect(slip.name, 'Weekend');

    final pick = PersonalSelection(
      fixtureId: '123', match: 'Casa - Ospite', market: 'Over 2.5',
      source: 'Combinazioni AI', capturedAt: DateTime(2026, 11, 22),
    );
    await store.addSelection(slip.id, pick);
    await store.addSelection(slip.id, pick);
    expect(store.coupons.last.selections.length, 1);

    await store.rename(slip.id, 'Preferite');
    expect(store.coupons.last.name, 'Preferite');
    await store.removeSelection(slip.id, '123', 'Over 2.5');
    expect(store.coupons.last.selections, isEmpty);
    await store.delete(slip.id);
    expect(store.coupons.where((e) => e.id == slip.id), isEmpty);
  });
}
