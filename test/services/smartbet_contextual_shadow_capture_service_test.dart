import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_dossier.dart';
import 'package:smartbet_ai_new/services/smartbet_contextual_shadow_capture_service.dart';
import 'package:smartbet_ai_new/services/smartbet_simulation_shadow_store.dart';

class _MemoryCaptureStore extends SmartBetSimulationShadowStore {
  SmartBetSimulationShadowSnapshot? last;
  int calls = 0;

  @override
  Future<bool> saveFirst(SmartBetSimulationShadowSnapshot snapshot) async {
    calls++;
    if (last != null && last!.key == snapshot.key) return false;
    last = snapshot;
    return true;
  }
}

MatchDossier _dossier({
  String kickoff = '2026-12-04T20:00:00Z',
  bool preMatch = true,
  bool richStats = true,
}) => MatchDossier(
  fixtureId: 402,
  homeTeam: 'Casa',
  awayTeam: 'Ospite',
  homeTeamId: 11,
  awayTeamId: 22,
  matchDate: kickoff,
  competition: 'Campionato',
  competitionId: 100,
  country: 'Italia',
  homeCurrentLeague: 'Serie A',
  homeCurrentLeagueId: 100,
  awayCurrentLeague: 'Serie A',
  awayCurrentLeagueId: 100,
  homeStatistics: richStats
      ? {
          'leagueId': 100,
          'matchesPlayed': 20,
          'goalsPerMatch': 1.9,
          'concededPerMatch': 1.0,
        }
      : const {},
  awayStatistics: richStats
      ? {
          'leagueId': 100,
          'matchesPlayed': 20,
          'goalsPerMatch': 1.1,
          'concededPerMatch': 1.7,
        }
      : const {},
  homeForm: const {'available': false},
  awayForm: const {'available': false},
  homeVenue: const {'matches': 10, 'winRate': 0.60},
  awayVenue: const {'matches': 10, 'winRate': 0.20},
  news: const [],
  injuries: const [],
  suspensions: const [],
  probableLineups: const [],
  marketInformation: const ['Quote di prova'],
  headToHead: const [],
  dataConfidence: 80,
  preMatchOnly: preMatch,
);

const _baseline = AnalysisResult(
  smartScore: 70,
  homeProbability: 45,
  drawProbability: 27,
  awayProbability: 28,
  over15Probability: 74,
  under15Probability: 26,
  over25Probability: 48,
  under25Probability: 52,
  goalProbability: 53,
  noGoalProbability: 47,
  expectedHomeGoals: 1.4,
  expectedAwayGoals: 1.1,
  prediction: '1X',
  valueBet: '',
  risk: '',
  explanation: '',
);

void main() {
  final observed = DateTime.utc(2026, 12, 3, 12);

  test(
    'P21V: dossier -> contestuale -> snapshot immutabile prepartita',
    () async {
      final store = _MemoryCaptureStore();
      final service = SmartBetContextualShadowCaptureService(store: store);
      final saved = await service.capture(
        fixtureId: 402,
        dossier: _dossier(),
        baseline: _baseline,
        recordedAt: observed,
      );
      expect(saved, isTrue);
      final snapshot = store.last!;
      expect(snapshot.engine, SmartBetContextualShadowCaptureService.engine);
      expect(
        snapshot.modelVersion,
        SmartBetContextualShadowCaptureService.modelVersion,
      );
      expect(snapshot.capturedAt.isBefore(snapshot.matchDate), isTrue);
      expect(snapshot.originalProbabilities['X'], closeTo(0.27, 1e-10));
      expect(snapshot.simulatedProbabilities.containsKey('X'), isTrue);
      expect(snapshot.expectedHomeGoals, isNot(closeTo(1.4, 1e-6)));
      expect(_baseline.homeProbability, 45); // nessun cambiamento live
      expect(store.calls, 1);
    },
  );

  test('P21V: secondo tentativo stessa partita non sovrascrive', () async {
    final store = _MemoryCaptureStore();
    final service = SmartBetContextualShadowCaptureService(store: store);
    expect(
      await service.capture(
        fixtureId: 402,
        dossier: _dossier(),
        baseline: _baseline,
        recordedAt: observed,
      ),
      isTrue,
    );
    expect(
      await service.capture(
        fixtureId: 402,
        dossier: _dossier(),
        baseline: _baseline,
        recordedAt: observed,
      ),
      isFalse,
    );
    expect(store.last!.capturedAt, observed);
  });

  test('P21V: dopo il calcio di inizio nessuno snapshot', () async {
    final store = _MemoryCaptureStore();
    final service = SmartBetContextualShadowCaptureService(store: store);
    expect(
      await service.capture(
        fixtureId: 402,
        dossier: _dossier(),
        baseline: _baseline,
        recordedAt: DateTime.utc(2026, 12, 5),
      ),
      isFalse,
    );
    expect(store.calls, 0);
  });

  test('P21V: non crea falso modello contestuale senza statistiche', () async {
    final store = _MemoryCaptureStore();
    final service = SmartBetContextualShadowCaptureService(store: store);
    expect(
      await service.capture(
        fixtureId: 402,
        dossier: _dossier(richStats: false),
        baseline: _baseline,
        recordedAt: observed,
      ),
      isFalse,
    );
    expect(store.calls, 0);
  });

  test(
    'P21V: non salva se dossier non prepartita o fixture differente',
    () async {
      final store = _MemoryCaptureStore();
      final service = SmartBetContextualShadowCaptureService(store: store);
      expect(
        await service.capture(
          fixtureId: 999,
          dossier: _dossier(),
          baseline: _baseline,
          recordedAt: observed,
        ),
        isFalse,
      );
      expect(
        await service.capture(
          fixtureId: 402,
          dossier: _dossier(preMatch: false),
          baseline: _baseline,
          recordedAt: observed,
        ),
        isFalse,
      );
      expect(store.calls, 0);
    },
  );
}
