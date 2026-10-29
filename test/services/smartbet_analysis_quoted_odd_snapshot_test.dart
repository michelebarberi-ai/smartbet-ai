import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime.utc(2026, 11, 1, 12);
  final kickoff = DateTime.utc(2026, 11, 2, 20);

  SmartBetAnalysisRecord sample({double? odd = 2.40}) {
    return SmartBetAnalysisRecord(
      engine: SmartBetAnalysisEngine.smartBet,
      fixtureId: 123456,
      homeTeam: 'Casa',
      awayTeam: 'Ospite',
      league: 'Test',
      country: 'IT',
      matchDate: kickoff,
      market: '1',
      probability: 0.65,
      smartScore: 75,
      confidence: null,
      classification: null,
      qualified: null,
      sources: const [SmartBetAnalysisSource.aiCoupon],
      prospectiveEligible: true,
      status: SmartBetAnalysisStatus.pending,
      actualHomeGoals: null,
      actualAwayGoals: null,
      firstSeenAt: start,
      lastSeenAt: start,
      quotedOdd: odd,
    );
  }

  test('Quota originale sopravvive alla serializzazione', () {
    final restored = SmartBetAnalysisRecord.fromJson(sample().toJson());

    expect(restored, isNotNull);
    expect(restored!.quotedOdd, 2.40);
  });

  test('Vecchio record senza quota resta compatibile', () {
    final raw = sample().toJson()..remove('quotedOdd');

    final restored = SmartBetAnalysisRecord.fromJson(raw);

    expect(restored, isNotNull);
    expect(restored!.quotedOdd, isNull);
    expect(restored.status, SmartBetAnalysisStatus.pending);
  });

  test('Aggiornamento source e risultato preservano la quota', () {
    final updated = sample().withSource(
      source: SmartBetAnalysisSource.combinations,
      seenAt: start.add(const Duration(minutes: 5)),
    );

    expect(updated.quotedOdd, 2.40);

    final resolved = updated.withActualResult(
      homeGoals: 2,
      awayGoals: 1,
      status: SmartBetAnalysisStatus.correct,
      updatedAt: kickoff.add(const Duration(hours: 3)),
    );

    expect(resolved.quotedOdd, 2.40);
    expect(resolved.status, SmartBetAnalysisStatus.correct);
  });

  test('Quote non valide non vengono ricaricate', () {
    for (final odd in [0.0, 1.0, -2.0, double.nan, double.infinity]) {
      final raw = sample().toJson();
      raw['quotedOdd'] = odd;

      final restored = SmartBetAnalysisRecord.fromJson(raw);

      expect(restored?.quotedOdd, isNull);
    }
  });

  test('Prima quota immutabile e persistenza dello storico', () async {
    SharedPreferences.setMockInitialValues({});

    final store = SmartBetAnalysisHistoryStore();

    Future<SmartBetAnalysisRecord?> register(
      double odd,
      SmartBetAnalysisSource source,
      DateTime at,
    ) {
      return store.registerAnalysis(
        engine: SmartBetAnalysisEngine.smartBet,
        source: source,
        fixtureId: 123456,
        homeTeam: 'Casa',
        awayTeam: 'Ospite',
        league: 'Test',
        country: 'IT',
        matchDate: kickoff,
        market: '1',
        probability: 0.65,
        smartScore: 75,
        recordedAt: at,
        quotedOdd: odd,
      );
    }

    await register(2.40, SmartBetAnalysisSource.aiCoupon, start);

    await register(
      3.10,
      SmartBetAnalysisSource.combinations,
      start.add(const Duration(minutes: 30)),
    );

    expect(store.records.length, 1);
    expect(store.records.single.quotedOdd, 2.40);

    final restoredStore = SmartBetAnalysisHistoryStore();
    await restoredStore.initialize();

    expect(restoredStore.records.length, 1);
    expect(restoredStore.records.single.quotedOdd, 2.40);
    expect(restoredStore.records.single.sources.length, 2);
  });
}
