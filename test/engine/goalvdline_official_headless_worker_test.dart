import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_official_coupon_contract.dart';
import 'package:smartbet_ai_new/services/settings_store.dart';
import 'package:smartbet_ai_new/services/smartbet_auto_coupon_service.dart';

/// P18: an explicitly launched, headless invocation of the exact production
/// SmartBetAutoCouponService. No second forecasting model and no phone data.
/// Skipped by normal `flutter test` runs. The dedicated host supplies the
/// request through an environment variable and reads an atomic result file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P18: esegue il motore ufficiale senza interfaccia',
    () async {
      HttpOverrides.global = null; // real network ONLY for opted-in worker
      final encoded = Platform.environment['GOALVDLINE_HEADLESS_REQUEST_B64'];
      final resultPath =
          Platform.environment['GOALVDLINE_HEADLESS_RESULT_PATH'];
      final revision = Platform.environment['GOALVDLINE_HEADLESS_REVISION'];
      if (encoded == null ||
          encoded.length > 8192 ||
          resultPath == null ||
          resultPath.isEmpty ||
          revision == null ||
          !RegExp(r'^[a-f0-9]{7,40}$').hasMatch(revision)) {
        throw StateError('P18: worker non configurato');
      }
      final decoded = jsonDecode(utf8.decode(base64.decode(encoded)));
      if (decoded is! Map<String, dynamic> ||
          decoded['protocol'] != 'goalvdline-official-coupon-v1' ||
          decoded['dayKey'] is! String ||
          decoded['generatedAfter'] is! String) {
        throw StateError('P18: richiesta non valida');
      }
      final preferences = GoalVdLineAutoCouponPreferences.fromJson(
        decoded['preferences'],
      );
      final after = DateTime.tryParse(decoded['generatedAfter'] as String);
      final start = DateTime.now().toUtc();
      if (preferences == null ||
          !preferences.requested ||
          after == null ||
          after.isAfter(start.add(const Duration(minutes: 1))) ||
          start.difference(after).inMinutes > 20) {
        throw StateError('P18: preferenze o data non valide');
      }

      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await SettingsStore.instance.initialize();
      await SettingsStore.instance.setMinimumSmartScore(65);

      final result = await SmartBetAutoCouponService().build(
        requestedEvents: preferences.events,
      );
      final completedAt = DateTime.now().toUtc();
      final coupon =
          preferences.systemMode ==
              GoalVdLineAutoCouponPreferences.threeSameFixtures
          ? GoalVdLineOfficialCouponContract.serializeThreeSet(
              coupons: result.coupons,
              preferences: preferences,
              now: completedAt,
            )
          : GoalVdLineOfficialCouponContract.serializeSet(
              coupons: result.coupons,
              preferences: preferences,
              now: completedAt,
            );
      final localNow = completedAt.add(
        Duration(hours: _romeOffset(completedAt)),
      );
      final dayKey =
          '${localNow.year.toString().padLeft(4, '0')}-'
          '${localNow.month.toString().padLeft(2, '0')}-'
          '${localNow.day.toString().padLeft(2, '0')}';
      if (dayKey != decoded['dayKey']) {
        throw StateError('P18: giorno locale cambiato durante l’analisi');
      }

      final output = <String, Object?>{
        'protocol': 'goalvdline-official-coupon-v1',
        'officialEngine': true,
        'revision': revision,
        'status': coupon == null ? 'no_eligible_coupon' : 'ready',
        'completedAt': completedAt.toIso8601String(),
        'coupon': coupon,
      };
      // Worker only: the runner controls an isolated random temp path.
      final file = File(resultPath);
      final temporary = File('$resultPath.tmp');
      await temporary.writeAsString(jsonEncode(output), flush: true);
      await temporary.rename(file.path);
      print('P18_ENGINE_STATUS=${output['status']}');
      print('P18_OFFICIAL_EVENTS=${(coupon?['events'] as List?)?.length ?? 0}');
    },
    skip: Platform.environment['GOALVDLINE_HEADLESS_RUN'] != '1',
    timeout: const Timeout(Duration(minutes: 19)),
  );
}

int _romeOffset(DateTime date) {
  final utc = date.toUtc();
  DateTime lastSunday(int month) {
    final lastDay = DateTime.utc(utc.year, month + 1, 0);
    return DateTime.utc(utc.year, month, lastDay.day - lastDay.weekday % 7, 1);
  }

  return !utc.isBefore(lastSunday(3)) && utc.isBefore(lastSunday(10)) ? 2 : 1;
}
