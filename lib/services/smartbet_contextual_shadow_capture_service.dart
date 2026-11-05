import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/match_dossier.dart';
import 'smartbet_contextual_simulation_service.dart';
import 'smartbet_simulation_bridge_service.dart';
import 'smartbet_simulation_shadow_store.dart';
import 'smartbet_sporting_odds_audit_service.dart';

/// P21V: connessione effettiva dossier -> simulatore contestuale -> snapshot.
/// Non effettua richieste di rete, non tocca le previsioni ufficiali.
/// Lo snapshot e' immutabile e valido solo prima del calcio d'inizio.
class SmartBetContextualShadowCaptureService {
  static const String engine = 'SMARTBET_CONTEXT';
  static const String modelVersion = 'p21v-contextual-poisson-v1';

  final SmartBetContextualSimulationService contextual;
  final SmartBetSportingOddsAuditService oddsAudit;
  final SmartBetSimulationBridgeService bridge;
  final SmartBetSimulationShadowStore store;

  const SmartBetContextualShadowCaptureService({
    this.contextual = const SmartBetContextualSimulationService(),
    this.oddsAudit = const SmartBetSportingOddsAuditService(),
    this.bridge = const SmartBetSimulationBridgeService(),
    required this.store,
  });

  /// Restituisce false se mancano dati, se e' tardi o se esiste gia' uno
  /// snapshot della stessa partita. Gli errori shadow non bloccano SmartBet.
  Future<bool> capture({
    required int fixtureId,
    required MatchDossier dossier,
    required AnalysisResult baseline,
    DateTime? recordedAt,
  }) async {
    try {
      final observed = (recordedAt ?? DateTime.now()).toUtc();
      final kickoff = DateTime.tryParse(dossier.matchDate)?.toUtc();
      if (fixtureId <= 0 ||
          fixtureId != dossier.fixtureId ||
          kickoff == null ||
          !observed.isBefore(kickoff) ||
          !dossier.preMatchOnly) {
        return false;
      }

      final report = contextual.evaluate(
        dossier: dossier,
        baseline: baseline,
        observedAt: observed,
      );
      final simulation = report.simulation;
      // Se P21J non ha applicato contesto, il modello P21A ha gia' lo
      // snapshot originale: non registriamo un secondo falso "contestuale".
      if (!report.eligible || !report.contextApplied || simulation == null) {
        return false;
      }

      // Audit locale metamorfologico: cambia solo marketInformation.
      // NON certifica il comportamento del backend remoto /analyze.
      final odds = oddsAudit.testMetadataInvariance(
        original: dossier,
        changedMarketMetadata: _withoutMarketMetadata(dossier),
        baseline: baseline,
        observedAt: observed,
      );
      if (!odds.passed || odds.testedMarkets == 0) return false;

      final native = bridge.fromSmartBet(
        result: baseline,
        fixtureId: fixtureId.toString(),
        dataQuality: report.dataQuality,
      );
      final original = <String, double>{};
      final adjusted = <String, double>{};
      final unsupported = <String>[];
      for (final entry in native.existingProbabilities.entries) {
        final probability = SmartBetSimulationMarketAdapter.forMarket(
          simulation,
          entry.key,
        );
        if (probability == null ||
            !probability.isFinite ||
            probability < 0 ||
            probability > 1) {
          unsupported.add(entry.key);
          continue;
        }
        original[entry.key] = entry.value;
        adjusted[entry.key] = probability;
      }
      if (original.isEmpty) return false;

      return await store.saveFirst(
        SmartBetSimulationShadowSnapshot(
          fixtureId: fixtureId,
          engine: engine,
          matchDate: kickoff,
          capturedAt: observed,
          modelVersion: modelVersion,
          expectedHomeGoals: simulation.input.expectedHomeGoals,
          expectedAwayGoals: simulation.input.expectedAwayGoals,
          dataQuality: report.dataQuality,
          originalProbabilities: original,
          simulatedProbabilities: adjusted,
          unsupportedMarkets: unsupported,
        ),
      );
    } catch (error) {
      debugPrint('SmartBet P21V contextual shadow unavailable: $error');
      return false;
    }
  }

  static MatchDossier _withoutMarketMetadata(MatchDossier d) => MatchDossier(
    fixtureId: d.fixtureId,
    homeTeam: d.homeTeam,
    awayTeam: d.awayTeam,
    homeTeamId: d.homeTeamId,
    awayTeamId: d.awayTeamId,
    matchDate: d.matchDate,
    competition: d.competition,
    competitionId: d.competitionId,
    country: d.country,
    homeCurrentLeague: d.homeCurrentLeague,
    homeCurrentLeagueId: d.homeCurrentLeagueId,
    awayCurrentLeague: d.awayCurrentLeague,
    awayCurrentLeagueId: d.awayCurrentLeagueId,
    homeStatistics: d.homeStatistics,
    homeForm: d.homeForm,
    homeVenue: d.homeVenue,
    awayStatistics: d.awayStatistics,
    awayForm: d.awayForm,
    awayVenue: d.awayVenue,
    news: d.news,
    injuries: d.injuries,
    suspensions: d.suspensions,
    probableLineups: d.probableLineups,
    marketInformation: const ['P21V - test di invarianza delle quote'],
    headToHead: d.headToHead,
    dataConfidence: d.dataConfidence,
    preMatchOnly: d.preMatchOnly,
  );
}
