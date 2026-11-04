import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/models/analysis_result.dart';
import 'package:smartbet_ai_new/models/match_dossier.dart';
import 'package:smartbet_ai_new/services/smartbet_contextual_simulation_service.dart';
import 'package:smartbet_ai_new/services/smartbet_sporting_odds_audit_service.dart';

AnalysisResult baseline({double home = 1.5, double away = 1.1}) =>
    AnalysisResult(
      smartScore: 65,
      homeProbability: 45,
      drawProbability: 28,
      awayProbability: 27,
      expectedHomeGoals: home,
      expectedAwayGoals: away,
      prediction: '1X',
      valueBet: '',
      risk: '',
      explanation: '',
    );

MatchDossier dossier({
  int quality = 85,
  bool preMatch = true,
  bool hasStatistics = true,
  List<String> marketInformation = const [],
  int homeLeague = 39,
}) => MatchDossier(
  fixtureId: 992001,
  homeTeam: 'Casa',
  awayTeam: 'Ospite',
  homeTeamId: 1,
  awayTeamId: 2,
  matchDate: '2026-12-10T18:00:00Z',
  competition: 'Campionato',
  competitionId: 39,
  country: 'Italia',
  homeCurrentLeague: 'Campionato',
  homeCurrentLeagueId: homeLeague,
  awayCurrentLeague: 'Campionato',
  awayCurrentLeagueId: 39,
  homeStatistics: hasStatistics
      ? const {
          'matchesPlayed': 22,
          'leagueId': 39,
          'goalsPerMatch': 2.0,
          'concededPerMatch': 0.9,
        }
      : const {},
  awayStatistics: hasStatistics
      ? const {
          'matchesPlayed': 21,
          'leagueId': 39,
          'goalsPerMatch': 0.9,
          'concededPerMatch': 1.6,
        }
      : const {},
  homeForm: const {'available': true},
  awayForm: const {'available': false},
  homeVenue: const {'matches': 11, 'winRate': 0.65},
  awayVenue: const {'matches': 11, 'winRate': 0.22},
  news: const [],
  injuries: const ['Casa: giocatore indisponibile'],
  suspensions: const [],
  probableLineups: const [],
  marketInformation: marketInformation,
  headToHead: const [],
  dataConfidence: quality,
  preMatchOnly: preMatch,
);

void main() {
  final asOf = DateTime.utc(2026, 12, 9);
  const service = SmartBetContextualSimulationService();
  test('P21J: applica statistiche ammissibili entro il 25%', () {
    final result = service.evaluate(
      dossier: dossier(),
      baseline: baseline(),
      observedAt: asOf,
    );
    expect(result.eligible, isTrue);
    expect(result.contextApplied, isTrue);
    expect(result.adjustedHomeGoals!, inInclusiveRange(1.5 * 0.75, 1.5 * 1.25));
    expect(result.adjustedAwayGoals!, inInclusiveRange(1.1 * 0.75, 1.1 * 1.25));
    expect(
      result.simulation!.homeWin +
          result.simulation!.draw +
          result.simulation!.awayWin,
      closeTo(1, 1e-9),
    );
  });
  test('P21J: nessuna analisi dopo il calcio di inizio', () {
    final result = service.evaluate(
      dossier: dossier(),
      baseline: baseline(),
      observedAt: DateTime.utc(2026, 12, 10, 19),
    );
    expect(result.eligible, isFalse);
    expect(result.simulation, isNull);
  });
  test('P21J: dossier non prepartita viene rifiutato', () {
    expect(
      service
          .evaluate(
            dossier: dossier(preMatch: false),
            baseline: baseline(),
            observedAt: asOf,
          )
          .eligible,
      isFalse,
    );
  });
  test('P21J: dati incompleti non inducono pseudo-miglioramenti', () {
    final result = service.evaluate(
      dossier: dossier(hasStatistics: false, quality: 15),
      baseline: baseline(),
      observedAt: asOf,
    );
    expect(result.contextApplied, isFalse);
    expect(result.adjustedHomeGoals, 1.5);
    expect(result.adjustedAwayGoals, 1.1);
  });
  test('P21J: evita statistiche di campionato diverso', () {
    final result = service.evaluate(
      dossier: dossier(homeLeague: 999),
      baseline: baseline(),
      observedAt: asOf,
    );
    expect(result.contextApplied, isFalse);
  });
  test('P21J: rifiuta gol attesi assenti', () {
    expect(
      service
          .evaluate(
            dossier: dossier(),
            baseline: baseline(home: 0),
            observedAt: asOf,
          )
          .eligible,
      isFalse,
    );
  });
  test('P21N: cambiare metadati quote non modifica lo scenario sportivo', () {
    final audit = const SmartBetSportingOddsAuditService()
        .testMetadataInvariance(
          original: dossier(marketInformation: const ['Quota X: 3.5']),
          changedMarketMetadata: dossier(
            marketInformation: const ['Quota X: 2.1', 'Mercato variato'],
          ),
          baseline: baseline(),
          observedAt: asOf,
        );
    expect(audit.passed, isTrue);
    expect(audit.testedMarkets, greaterThan(10));
    expect(audit.maximumDifference, 0);
  });
  test('P21N: rifiuta confronti dove cambiano anche dati sportivi', () {
    expect(
      () => const SmartBetSportingOddsAuditService().testMetadataInvariance(
        original: dossier(),
        changedMarketMetadata: dossier(homeLeague: 44),
        baseline: baseline(),
        observedAt: asOf,
      ),
      throwsArgumentError,
    );
  });
}
