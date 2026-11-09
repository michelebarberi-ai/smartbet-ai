import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('B45 P5: configurazione iniziale OFF, 08:00 e soglia 65%', () async {
    final value = await const GoalVdLineAutoCouponPreferencesStore().load();
    expect(value.requested, isFalse);
    expect(value.formattedTime, '08:00');
    expect(value.events, 4);
    expect(value.minimumMarketProbability, 65);
    expect(value.market, GoalVdLineAutoCouponPreferences.multiMarket);
    expect(value.notifyChanges, isTrue);
  });

  test('B45 P5: salva e ricarica tutte le preferenze sul telefono', () async {
    const store = GoalVdLineAutoCouponPreferencesStore();
    final value = const GoalVdLineAutoCouponPreferences().copyWith(
      requested: true,
      hour: 7,
      minute: 35,
      events: 5,
      minimumMarketProbability: 75,
      market: GoalVdLineAutoCouponPreferences.overUnder,
      notifyChanges: false,
    );
    expect(await store.save(value), isTrue);
    final restored = await store.load();
    expect(restored.requested, isTrue);
    expect(restored.formattedTime, '07:35');
    expect(restored.events, 5);
    expect(restored.minimumMarketProbability, 75);
    expect(restored.market, GoalVdLineAutoCouponPreferences.overUnder);
    expect(restored.notifyChanges, isFalse);
  });

  test('B45 P5: nessuna attivazione con JSON malformato', () async {
    SharedPreferences.setMockInitialValues({
      GoalVdLineAutoCouponPreferencesStore.storageKey: '{invalid',
    });
    expect(
      (await const GoalVdLineAutoCouponPreferencesStore().load()).requested,
      isFalse,
    );
  });

  test('B45 P5: dati di configurazione invalidi falliscono chiusi', () async {
    SharedPreferences.setMockInitialValues({
      GoalVdLineAutoCouponPreferencesStore.storageKey: jsonEncode({
        'requested': true,
        'hour': 27,
        'minute': 0,
        'events': 7,
        'minimumMarketProbability': 1,
        'market': 'NON_ESISTE',
        'notifyChanges': true,
      }),
    });
    final value = await const GoalVdLineAutoCouponPreferencesStore().load();
    expect(value.requested, isFalse);
    expect(value.formattedTime, '08:00');
  });

  test('B45 P5: non salva orari o soglie impossibili', () async {
    const store = GoalVdLineAutoCouponPreferencesStore();
    expect(
      await store.save(
        const GoalVdLineAutoCouponPreferences(requested: true, minute: 60),
      ),
      isFalse,
    );
    expect(
      await store.save(
        const GoalVdLineAutoCouponPreferences(
          requested: true,
          minimumMarketProbability: 73,
        ),
      ),
      isFalse,
    );
    expect((await store.load()).requested, isFalse);
  });

  test('B45 P5: disattivazione esplicita persiste', () async {
    const store = GoalVdLineAutoCouponPreferencesStore();
    expect(
      await store.save(const GoalVdLineAutoCouponPreferences(requested: true)),
      isTrue,
    );
    expect(
      await store.save(const GoalVdLineAutoCouponPreferences(requested: false)),
      isTrue,
    );
    expect((await store.load()).requested, isFalse);
  });

  test('B45 P5: errore del disco non abilita alcun programma', () async {
    final store = GoalVdLineAutoCouponPreferencesStore(
      preferencesLoader: () async => throw StateError('disco non disponibile'),
    );
    expect(
      await store.save(const GoalVdLineAutoCouponPreferences(requested: true)),
      isFalse,
    );
    expect((await store.load()).requested, isFalse);
  });
}
