import 'dart:math' as math;

import '../models/analysis_result.dart';
import '../models/match_dossier.dart';
import 'smartbet_match_simulation_service.dart';

/// P21J/P21N: simulazione di contesto SHADOW basata esclusivamente su
/// dati prepartita gia' inclusi nel dossier. Nessuna chiamata API o quote.
/// La forma testuale, le assenze e le formazioni non producono aggiustamenti
/// numerici finche' non sono disponibili input strutturati e validati.
class SmartBetContextualSimulationReport {
  final SmartBetSimulationResult? simulation;
  final bool eligible;
  final bool contextApplied;
  final double? baselineHomeGoals;
  final double? baselineAwayGoals;
  final double? adjustedHomeGoals;
  final double? adjustedAwayGoals;
  final double dataQuality;
  final List<String> evidenceUsed;
  final List<String> limitations;

  const SmartBetContextualSimulationReport({
    required this.simulation,
    required this.eligible,
    required this.contextApplied,
    required this.baselineHomeGoals,
    required this.baselineAwayGoals,
    required this.adjustedHomeGoals,
    required this.adjustedAwayGoals,
    required this.dataQuality,
    required this.evidenceUsed,
    required this.limitations,
  });

  Map<String, Object?> toJson() => {
    'schema': 'smartbet_p21j_context_shadow_v1',
    'mode': 'shadow_only',
    'eligible': eligible,
    'contextApplied': contextApplied,
    'baselineHomeGoals': baselineHomeGoals,
    'baselineAwayGoals': baselineAwayGoals,
    'adjustedHomeGoals': adjustedHomeGoals,
    'adjustedAwayGoals': adjustedAwayGoals,
    'dataQuality': dataQuality,
    'used': evidenceUsed,
    'limitations': limitations,
    'drawProbability': simulation?.draw,
    'modelVersion': SmartBetMatchSimulationService.modelVersion,
  };
}

class SmartBetContextualSimulationService {
  final SmartBetMatchSimulationService simulator;

  const SmartBetContextualSimulationService({
    this.simulator = const SmartBetMatchSimulationService(),
  });

  /// `observedAt` viene fornito dal chiamante, mai ricavato dal risultato
  /// finale. Non usare per confronti retrospettivi senza snapshot originali.
  SmartBetContextualSimulationReport evaluate({
    required MatchDossier dossier,
    required AnalysisResult baseline,
    required DateTime observedAt,
  }) {
    final used = <String>[];
    final limitations = <String>[];
    final kickoff = DateTime.tryParse(dossier.matchDate)?.toUtc();
    final quality = dossier.dataConfidence.clamp(0, 100) / 100.0;
    final h = baseline.expectedHomeGoals;
    final a = baseline.expectedAwayGoals;

    if (!dossier.preMatchOnly ||
        kickoff == null ||
        !observedAt.toUtc().isBefore(kickoff)) {
      return SmartBetContextualSimulationReport(
        simulation: null,
        eligible: false,
        contextApplied: false,
        baselineHomeGoals: h,
        baselineAwayGoals: a,
        adjustedHomeGoals: null,
        adjustedAwayGoals: null,
        dataQuality: quality,
        evidenceUsed: const [],
        limitations: const [
          'Dossier non certificato prepartita o osservazione tardiva.',
        ],
      );
    }
    if (!h.isFinite || !a.isFinite || h <= 0 || a <= 0 || h > 6 || a > 6) {
      return SmartBetContextualSimulationReport(
        simulation: null,
        eligible: false,
        contextApplied: false,
        baselineHomeGoals: h,
        baselineAwayGoals: a,
        adjustedHomeGoals: null,
        adjustedAwayGoals: null,
        dataQuality: quality,
        evidenceUsed: const [],
        limitations: const ['Gol attesi iniziali mancanti o invalidi.'],
      );
    }

    double home = h;
    double away = a;
    if (quality < 0.3) {
      limitations.add('Qualita dossier insufficiente: contesto non applicato.');
    } else {
      final homeGames = _number(dossier.homeStatistics['matchesPlayed']);
      final awayGames = _number(dossier.awayStatistics['matchesPlayed']);
      final homeFor = _number(dossier.homeStatistics['goalsPerMatch']);
      final homeConceded = _number(dossier.homeStatistics['concededPerMatch']);
      final awayFor = _number(dossier.awayStatistics['goalsPerMatch']);
      final awayConceded = _number(dossier.awayStatistics['concededPerMatch']);
      final sameHomeLeague = _sameLeague(
        dossier.homeStatistics['leagueId'],
        dossier.homeCurrentLeagueId,
      );
      final sameAwayLeague = _sameLeague(
        dossier.awayStatistics['leagueId'],
        dossier.awayCurrentLeagueId,
      );

      if (homeGames != null &&
          awayGames != null &&
          homeGames >= 6 &&
          awayGames >= 6 &&
          homeFor != null &&
          awayConceded != null &&
          awayFor != null &&
          homeConceded != null &&
          homeFor >= 0 &&
          awayFor >= 0 &&
          homeConceded >= 0 &&
          awayConceded >= 0 &&
          homeFor <= 6 &&
          awayFor <= 6 &&
          homeConceded <= 6 &&
          awayConceded <= 6 &&
          sameHomeLeague &&
          sameAwayLeague) {
        final sample = math.min(homeGames, awayGames);
        final weight = math.min(
          0.25,
          (sample / (sample + 30.0)) * quality * 0.35,
        );
        final statisticalHome = math.sqrt(homeFor * awayConceded);
        final statisticalAway = math.sqrt(awayFor * homeConceded);
        if (statisticalHome > 0 && statisticalAway > 0) {
          home = h * (1 - weight) + statisticalHome * weight;
          away = a * (1 - weight) + statisticalAway * weight;
          used.add('Gol segnati/subiti per gara, campione e lega verificati.');
        } else {
          limitations.add(
            'Statistiche offensive troppo deboli per la correzione.',
          );
        }
      } else {
        limitations.add(
          'Statistiche mancanti, campione insufficiente o lega fonte diversa.',
        );
      }

      // Piccola correzione venue, solo con campioni significativi.
      // Non confonde la frequenza delle vittorie con una probabilita 1X2.
      final homeVenueGames = _number(dossier.homeVenue['matches']);
      final awayVenueGames = _number(dossier.awayVenue['matches']);
      final homeVenueRate = _number(dossier.homeVenue['winRate']);
      final awayVenueRate = _number(dossier.awayVenue['winRate']);
      if (homeVenueGames != null &&
          awayVenueGames != null &&
          homeVenueGames >= 6 &&
          awayVenueGames >= 6 &&
          homeVenueRate != null &&
          awayVenueRate != null &&
          homeVenueRate >= 0 &&
          homeVenueRate <= 1 &&
          awayVenueRate >= 0 &&
          awayVenueRate <= 1 &&
          sameHomeLeague &&
          sameAwayLeague) {
        final shift = ((homeVenueRate - awayVenueRate) * 0.04 * quality).clamp(
          -0.04,
          0.04,
        );
        home *= 1 + shift;
        away *= 1 - shift;
        used.add('Rendimento casa/trasferta con campioni verificati.');
      } else {
        limitations.add('Dati casa/trasferta insufficienti.');
      }
    }

    if (dossier.injuries.isNotEmpty || dossier.suspensions.isNotEmpty) {
      limitations.add(
        'Assenze note ma non pesate: manca impatto giocatore validato.',
      );
    }
    if (dossier.probableLineups.isNotEmpty) {
      limitations.add('Formazioni testuali non convertite in forza giocatori.');
    }
    if (dossier.homeForm['available'] == true ||
        dossier.awayForm['available'] == true) {
      limitations.add('Forma testuale disponibile, non ancora quantificata.');
    }
    limitations.add('Contesto tattico e fase minuto-per-minuto non modellati.');

    // Bound prudente contro outlier e cambiamenti incontrollati.
    home = home
        .clamp(math.max(0.01, h * 0.75), math.min(6.0, h * 1.25))
        .toDouble();
    away = away
        .clamp(math.max(0.01, a * 0.75), math.min(6.0, a * 1.25))
        .toDouble();
    final simulation = simulator.simulate(
      SmartBetMatchSimulationInput(
        expectedHomeGoals: home,
        expectedAwayGoals: away,
        dataQuality: quality,
      ),
    );
    return SmartBetContextualSimulationReport(
      simulation: simulation,
      eligible: true,
      contextApplied: used.isNotEmpty,
      baselineHomeGoals: h,
      baselineAwayGoals: a,
      adjustedHomeGoals: home,
      adjustedAwayGoals: away,
      dataQuality: quality,
      evidenceUsed: List.unmodifiable(used),
      limitations: List.unmodifiable(limitations),
    );
  }

  static bool _sameLeague(Object? league, int current) {
    final value = _number(league);
    return current > 0 && value != null && value.toInt() == current;
  }

  static double? _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }
}
