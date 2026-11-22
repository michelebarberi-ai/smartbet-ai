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
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('goalvdline_personal_coupons_v1'),
        contains('Weekend'));

    final pick = PersonalSelection(
      fixtureId: '123', match: 'Casa - Ospite', market: 'Over 2.5',
      source: 'Combinazioni AI', capturedAt: DateTime(2026, 11, 22),
      probability: 76.5, odds: 1.82,
    );
    expect(await store.addSelection(slip.id, pick), isTrue);
    expect(await store.addSelection(slip.id, pick), isFalse);
    expect(await store.addSelection(slip.id, PersonalSelection(
      fixtureId: '123', match: 'Casa - Ospite', market: ' over 2.5 ',
      source: 'Analisi Partite', capturedAt: DateTime(2026, 11, 22),
    )), isFalse);
    expect(store.coupons.last.selections.length, 1);
    final restored = PersonalCoupon.fromJson(store.coupons.last.toJson());
    expect(restored.selections.single.odds, 1.82);
    expect(restored.selections.single.probability, 76.5);
    // Another market on the same fixture is allowed, but reviewed in the UI.
    expect(await store.addSelection(slip.id, PersonalSelection(
      fixtureId: '123', match: 'Casa - Ospite', market: 'Goal',
      source: 'Analisi Partite', capturedAt: DateTime(2026, 11, 22),
    )), isTrue);
    expect(store.coupons.last.selections.length, 2);

    await store.rename(slip.id, 'Preferite');
    expect(store.coupons.last.name, 'Preferite');
    await store.removeSelection(slip.id, '123', 'Over 2.5');
    expect(store.coupons.last.selections.length, 1);
    await store.removeSelection(slip.id, '123', 'Goal');
    expect(store.coupons.last.selections, isEmpty);
    await store.delete(slip.id);
    expect(store.coupons.where((e) => e.id == slip.id), isEmpty);
  });
}
