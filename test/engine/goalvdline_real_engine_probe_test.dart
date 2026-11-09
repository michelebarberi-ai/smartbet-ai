import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartbet_ai_new/services/goalvdline_auto_coupon_preferences.dart';
import 'package:smartbet_ai_new/services/goalvdline_official_coupon_contract.dart';
import 'package:smartbet_ai_new/services/smartbet_auto_coupon_service.dart';
import 'package:smartbet_ai_new/services/smartbet_coupon_service.dart';

/// B45 / P17: a read-only, opt-in integration probe against real football data.
///
/// This calls the same Flutter engine used by the app (SmartBetAutoCouponService).
/// It does NOT implement a second model, perform a bet, upload predictions, or
/// claim that the server can run Flutter yet. Never enable it in routine CI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P17: genera una schedina col motore ufficiale e verifica il contratto',
    () async {
      // Flutter tests normally replace the HTTP client with a fake one.
      // Only this explicitly opted-in probe may use the real network.
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();

      const preferences = GoalVdLineAutoCouponPreferences(
        requested: true,
        events: 3,
        minimumMarketProbability: 65,
        market: GoalVdLineAutoCouponPreferences.multiMarket,
      );

      final startedAt = DateTime.now().toUtc();
      final result = await SmartBetAutoCouponService().build();
      final checkedAt = DateTime.now().toUtc();
      final coupon = GoalVdLineOfficialCouponContract.serializeSet(
        coupons: result.coupons,
        preferences: preferences,
        now: checkedAt,
      );

      // Diagnostica P17: osserva solo le selezioni dei profili ufficiali.
      // Non cambia quote, soglie, pronostici o priorita dei profili.
      final profiles = <String, SmartBetCouponResult>{
        'premium': result.coupons.premium,
        'balanced': result.coupons.balanced,
        'value': result.coupons.value,
      };
      final profileDiagnostics = <String, Map<String, Object>>{};
      for (final entry in profiles.entries) {
        final selections = entry.value.selections;
        print(
          'P17_MARKETS_${entry.key.toUpperCase()}=${jsonEncode(selections.map((s) => s.sportsPick?.market).toList())}',
        );
        final details = <String, Object>{
          'selections': selections.length,
          'validMarketPicks': selections.where((s) {
            final market = s.sportsPick?.market;
            return market != null &&
                GoalVdLineOfficialCouponContract.marketFamily(market) != null;
          }).length,
          'probabilityAtLeast65': selections
              .where(
                (s) =>
                    s.effectiveProbabilityPercent >=
                    preferences.minimumMarketProbability,
              )
              .length,
          'validRealOdds': selections
              .where(
                (s) =>
                    s.sportsPick != null &&
                    s.sportsPick!.odd.isFinite &&
                    s.sportsPick!.odd > 1.0,
              )
              .length,
          'futureKickoff': selections.where((s) {
            final instant = DateTime.tryParse(s.match.date)?.toUtc();
            return instant != null && instant.isAfter(checkedAt);
          }).length,
          'upcomingStatus': selections.where((s) {
            final status = s.match.statusShort.trim().toUpperCase();
            return status.isEmpty || status == 'NS';
          }).length,
          'exported3':
              GoalVdLineOfficialCouponContract.serialize(
                coupon: entry.value,
                preferences: preferences,
                now: checkedAt,
              ) !=
              null,
          'message': entry.value.message,
        };
        profileDiagnostics[entry.key] = details;
        print('P17_PROFILE_${entry.key.toUpperCase()}=${jsonEncode(details)}');
      }

      // A no-coupon result is legitimate. It MUST NOT turn into invented events.
      final status = coupon == null
          ? 'no_eligible_coupon'
          : 'valid_official_coupon';
      final report = <String, Object?>{
        'probe': 'goalvdline-b45-p17-official-engine-v1',
        'status': status,
        'startedAt': startedAt.toIso8601String(),
        'checkedAt': checkedAt.toIso8601String(),
        'totalMatches': result.totalMatches,
        'metadataCandidates': result.metadataCandidates,
        'preliminaryAnalyzed': result.preliminaryAnalyzed,
        'preliminaryValid': result.preliminaryValid,
        'advancedCandidates': result.advancedCandidates,
        'requestedEvents': preferences.events,
        'minimumMarketProbability': preferences.minimumMarketProbability,
        'profiles': profileDiagnostics,
        'coupon': coupon,
      };

      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final output = File('$home/Downloads/GoalVdLine_P17_Engine_Probe.json');
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
        // No tokens, database credentials or user identity are included.
        print('P17_REPORT=${output.path}');
      }
      print('P17_ENGINE_STATUS=$status');
      print('P17_MATCHES=${result.totalMatches}');
      print('P17_METADATA_CANDIDATES=${result.metadataCandidates}');
      print('P17_PRELIMINARY_ANALYZED=${result.preliminaryAnalyzed}');
      print('P17_PRELIMINARY_VALID=${result.preliminaryValid}');
      print('P17_ADVANCED_CANDIDATES=${result.advancedCandidates}');
      print('P17_OFFICIAL_EVENTS=${(coupon?['events'] as List?)?.length ?? 0}');
    },
    // A user must opt in explicitly because the engine uses real HTTP APIs.
    skip: Platform.environment['GOALVDLINE_REAL_ENGINE_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
