import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/smartbet_analysis_history_store.dart';

final kickoff = DateTime.utc(2026, 11, 20, 17);
final observed = kickoff.add(const Duration(hours: 5));

SmartBetAnalysisRecord old({
  required int fixture,
  required String market,
  bool prospective = true,
  DateTime? knownAt,
}) => SmartBetAnalysisRecord(
  engine: SmartBetAnalysisEngine.smartBet,
  fixtureId: fixture,
  homeTeam: 'Casa', awayTeam: 'Ospite',
  league: 'Serie A', country: 'Italia',
  matchDate: kickoff,
  market: market,
  probability: 0.8,
  smartScore: 80,
  confidence: null,
  classification: null,
  qualified: null,
  sources: const [SmartBetAnalysisSource.analysis],
  prospectiveEligible: prospective,
  status: SmartBetAnalysisStatus.unsupported,
  actualHomeGoals: 2, actualAwayGoals: 1,
  firstSeenAt: kickoff.subtract(const Duration(days: 1)),
  lastSeenAt: observed,
  resolvedAt: knownAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B78: local legacy OR outcomes are reclassified without fetching results',
      () async {
    final oldRecords = [
      old(fixture: 801, market: 'GOAL O OVER 2.5', knownAt: observed),
      old(fixture: 802, market: 'X O UNDER 2.5', knownAt: observed),
      old(fixture: 803, market: 'GOAL O UNDER', knownAt: observed),
      old(fixture: 804, market: 'GOAL O OVER 2.5',
          prospective: false, knownAt: observed),
      old(fixture: 805, market: 'GOAL O OVER 2.5', knownAt: null),
    ];
    SharedPreferences.setMockInitialValues({
      'smartbet_analysis_history_v1':
          jsonEncode(oldRecords.map((r) => r.toJson()).toList()),
    });
    final store = SmartBetAnalysisHistoryStore();
    await store.initialize();
    final statuses = {
      for (final entry in store.records) entry.fixtureId: entry.status,
    };
    expect(statuses[801], SmartBetAnalysisStatus.correct);
    expect(statuses[802], SmartBetAnalysisStatus.wrong);
    expect(statuses[803], SmartBetAnalysisStatus.unsupported);
    expect(statuses[804], SmartBetAnalysisStatus.unsupported);
    expect(statuses[805], SmartBetAnalysisStatus.unsupported);

    final migrated = store.records.singleWhere((r) => r.fixtureId == 801);
    expect(migrated.outcomeKnownBy, observed);
    expect(migrated.firstSeenAt, oldRecords.first.firstSeenAt);
    expect(migrated.probability, 0.8);

    // The reconciliation is idempotent and survives disk reload.
    final second = SmartBetAnalysisHistoryStore();
    await second.initialize();
    expect(second.records.singleWhere((r) => r.fixtureId == 801).status,
        SmartBetAnalysisStatus.correct);
    expect(second.records.singleWhere((r) => r.fixtureId == 803).status,
        SmartBetAnalysisStatus.unsupported);
  });
}
