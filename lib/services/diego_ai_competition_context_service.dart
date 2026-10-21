import '../managers/league_manager.dart';
import '../models/match_dossier.dart';
import '../models/match_model.dart';
import 'historical_team_service.dart';
import 'team_data_resolver.dart';

class DiegoCompetitionTeamContext {
  final int teamId;
  final String teamName;

  final int domesticLeagueId;
  final String domesticLeagueName;

  final double domesticLeagueWeight;
  final bool domesticLeagueWeightIsFallback;

  final int? competitionSeason;
  final HistoricalTeamData? competitionHistory;

  final Map<int, ResolvedTeamLeague> opponentLeagues;

  const DiegoCompetitionTeamContext({
    required this.teamId,
    required this.teamName,
    required this.domesticLeagueId,
    required this.domesticLeagueName,
    required this.domesticLeagueWeight,
    required this.domesticLeagueWeightIsFallback,
    required this.competitionSeason,
    required this.competitionHistory,
    this.opponentLeagues = const {},
  });
}

class DiegoCompetitionAdjustment {
  final double homeAdjustment;
  final double awayAdjustment;

  final double homePerformanceScore;
  final double awayPerformanceScore;

  final double homeSampleFactor;
  final double awaySampleFactor;

  final int homeMainStageMatches;
  final int awayMainStageMatches;

  final int homeKnownOpponents;
  final int awayKnownOpponents;

  final bool leagueComparisonAvailable;
  final double leagueSignal;

  const DiegoCompetitionAdjustment({
    required this.homeAdjustment,
    required this.awayAdjustment,
    required this.homePerformanceScore,
    required this.awayPerformanceScore,
    required this.homeSampleFactor,
    required this.awaySampleFactor,
    required this.homeMainStageMatches,
    required this.awayMainStageMatches,
    required this.homeKnownOpponents,
    required this.awayKnownOpponents,
    required this.leagueComparisonAvailable,
    required this.leagueSignal,
  });

  static const neutral = DiegoCompetitionAdjustment(
    homeAdjustment: 0.0,
    awayAdjustment: 0.0,
    homePerformanceScore: 0.0,
    awayPerformanceScore: 0.0,
    homeSampleFactor: 0.0,
    awaySampleFactor: 0.0,
    homeMainStageMatches: 0,
    awayMainStageMatches: 0,
    homeKnownOpponents: 0,
    awayKnownOpponents: 0,
    leagueComparisonAvailable: false,
    leagueSignal: 0.0,
  );
}

class _CompetitionPerformanceEvidence {
  final double score;
  final double sampleFactor;
  final double adjustment;

  final int matches;
  final int knownOpponents;

  const _CompetitionPerformanceEvidence({
    required this.score,
    required this.sampleFactor,
    required this.adjustment,
    required this.matches,
    required this.knownOpponents,
  });
}

class DiegoCompetitionContext {
  final int competitionId;
  final String competitionName;
  final DateTime referenceDate;

  final DiegoCompetitionTeamContext home;
  final DiegoCompetitionTeamContext away;

  const DiegoCompetitionContext({
    required this.competitionId,
    required this.competitionName,
    required this.referenceDate,
    required this.home,
    required this.away,
  });

  DiegoCompetitionAdjustment calculateAdjustment() {
    final homePerformance = _competitionPerformance(home);
    final awayPerformance = _competitionPerformance(away);

    var homeAdjustment = homePerformance.adjustment;
    var awayAdjustment = awayPerformance.adjustment;

    // D2B.2:
    // aiWeight NON rappresenta la forza relativa del campionato.
    // Finché non avremo un leagueStrength realmente calibrato,
    // il confronto tra campionati resta intenzionalmente neutro.
    const leagueComparisonAvailable = false;
    const leagueSignal = 0.0;

    homeAdjustment = homeAdjustment.clamp(-0.08, 0.08).toDouble();

    awayAdjustment = awayAdjustment.clamp(-0.08, 0.08).toDouble();

    return DiegoCompetitionAdjustment(
      homeAdjustment: homeAdjustment,
      awayAdjustment: awayAdjustment,
      homePerformanceScore: homePerformance.score,
      awayPerformanceScore: awayPerformance.score,
      homeSampleFactor: homePerformance.sampleFactor,
      awaySampleFactor: awayPerformance.sampleFactor,
      homeMainStageMatches: homePerformance.matches,
      awayMainStageMatches: awayPerformance.matches,
      homeKnownOpponents: homePerformance.knownOpponents,
      awayKnownOpponents: awayPerformance.knownOpponents,
      leagueComparisonAvailable: leagueComparisonAvailable,
      leagueSignal: leagueSignal,
    );
  }

  _CompetitionPerformanceEvidence _competitionPerformance(
    DiegoCompetitionTeamContext team,
  ) {
    final history = team.competitionHistory;

    if (history == null || history.fixtures.isEmpty) {
      return const _CompetitionPerformanceEvidence(
        score: 0.0,
        sampleFactor: 0.0,
        adjustment: 0.0,
        matches: 0,
        knownOpponents: 0,
      );
    }

    final fixtures = history.fixtures
        .where(
          (fixture) => _competitionPhase(fixture.round) == 'FASE PRINCIPALE',
        )
        .toList();

    if (fixtures.isEmpty) {
      return const _CompetitionPerformanceEvidence(
        score: 0.0,
        sampleFactor: 0.0,
        adjustment: 0.0,
        matches: 0,
        knownOpponents: 0,
      );
    }

    var weightedSignal = 0.0;
    var evidenceWeightTotal = 0.0;
    var knownOpponents = 0;

    for (final fixture in fixtures) {
      double resultSignal;

      if (fixture.result == 'V') {
        resultSignal = 1.0;
      } else if (fixture.result == 'S') {
        resultSignal = -1.0;
      } else {
        resultSignal = 0.0;
      }

      final goalDifference = fixture.goalsFor - fixture.goalsAgainst;

      final marginSignal = (goalDifference / 3.0).clamp(-1.0, 1.0).toDouble();

      final matchSignal = (resultSignal * 0.65) + (marginSignal * 0.35);

      final opponentLeague = team.opponentLeagues[fixture.opponentId];

      final managedLeague = opponentLeague == null
          ? null
          : LeagueManager.findById(opponentLeague.leagueId);

      // N/D non significa "avversario debole".
      // Riduciamo soltanto il peso dell'evidenza.
      final evidenceWeight = managedLeague == null ? 0.60 : 1.00;

      if (managedLeague != null) {
        knownOpponents++;
      }

      weightedSignal += matchSignal * evidenceWeight;
      evidenceWeightTotal += evidenceWeight;
    }

    final score = evidenceWeightTotal <= 0
        ? 0.0
        : (weightedSignal / evidenceWeightTotal).clamp(-1.0, 1.0).toDouble();

    // Shrinkage:
    // 2 partite -> 0.333
    // 4 partite -> 0.500
    // 6 partite -> 0.600
    final sampleFactor = fixtures.length / (fixtures.length + 4.0);

    final adjustment = (score * sampleFactor * 0.10)
        .clamp(-0.10, 0.10)
        .toDouble();

    return _CompetitionPerformanceEvidence(
      score: score,
      sampleFactor: sampleFactor,
      adjustment: adjustment,
      matches: fixtures.length,
      knownOpponents: knownOpponents,
    );
  }

  void logAdjustment(DiegoCompetitionAdjustment adjustment) {
    print('');
    print('========================================');
    print('DIEGO COMPETITION ADJUSTMENT - D2B.1');
    print('========================================');

    print(
      '${home.teamName}: '
      'performance=${adjustment.homePerformanceScore.toStringAsFixed(3)} | '
      'sample=${adjustment.homeSampleFactor.toStringAsFixed(3)} | '
      'mainStage=${adjustment.homeMainStageMatches} | '
      'oppKnown=${adjustment.homeKnownOpponents} | '
      'context=${(adjustment.homeAdjustment * 100).toStringAsFixed(2)}%',
    );

    print(
      '${away.teamName}: '
      'performance=${adjustment.awayPerformanceScore.toStringAsFixed(3)} | '
      'sample=${adjustment.awaySampleFactor.toStringAsFixed(3)} | '
      'mainStage=${adjustment.awayMainStageMatches} | '
      'oppKnown=${adjustment.awayKnownOpponents} | '
      'context=${(adjustment.awayAdjustment * 100).toStringAsFixed(2)}%',
    );

    if (adjustment.leagueComparisonAvailable) {
      print(
        'Confronto campionati: DISPONIBILE | '
        'signal=${adjustment.leagueSignal.toStringAsFixed(3)}',
      );
    } else {
      print(
        'Confronto campionati: N/D '
        '(almeno una lega non calibrata)',
      );
    }

    print('QUOTE UTILIZZATE: NO');
    print('========================================');
  }

  void logShadow() {
    print('');
    print('========================================');
    print('DIEGO COMPETITION CONTEXT - SHADOW');
    print('========================================');
    print('Competizione: $competitionName');
    print('Competition ID: $competitionId');
    print('Data riferimento: ${referenceDate.toIso8601String()}');

    _logTeam(home);
    _logTeam(away);

    print('========================================');
    print('SHADOW ONLY: nessun impatto sulle probabilità');
    print('========================================');
  }

  void _logTeam(DiegoCompetitionTeamContext team) {
    print('');
    print('----------------------------------------');
    print(team.teamName);
    print('----------------------------------------');

    final domesticName = team.domesticLeagueName.trim().isEmpty
        ? 'N/D'
        : team.domesticLeagueName;

    print('Campionato domestico: $domesticName');
    print('Campionato ID: ${team.domesticLeagueId}');

    final weightSuffix = team.domesticLeagueWeightIsFallback
        ? ' (fallback)'
        : '';

    print(
      'Peso campionato: '
      '${team.domesticLeagueWeight.toStringAsFixed(2)}'
      '$weightSuffix',
    );

    final history = team.competitionHistory;

    if (history == null || history.matchesPlayed == 0) {
      print('Storico stessa competizione: N/D');
      return;
    }

    print('Stagione competizione: ${team.competitionSeason ?? history.season}');
    print('Partite stessa competizione: ${history.matchesPlayed}');
    print(
      'Record competizione: '
      '${history.wins}V / ${history.draws}X / ${history.losses}S',
    );
    print(
      'Gol competizione: '
      '${history.goalsFor} fatti / ${history.goalsAgainst} subiti',
    );
    print(
      'Casa: '
      '${history.homeWins}V / '
      '${history.homeDraws}X / '
      '${history.homeLosses}S '
      '(${history.homeMatches} partite)',
    );
    print(
      'Trasferta: '
      '${history.awayWins}V / '
      '${history.awayDraws}X / '
      '${history.awayLosses}S '
      '(${history.awayMatches} partite)',
    );

    if (history.fixtures.isNotEmpty) {
      final qualifyingFixtures = history.fixtures
          .where(
            (fixture) => _competitionPhase(fixture.round) == 'QUALIFICAZIONE',
          )
          .toList();

      final mainStageFixtures = history.fixtures
          .where(
            (fixture) => _competitionPhase(fixture.round) == 'FASE PRINCIPALE',
          )
          .toList();

      final otherFixtures = history.fixtures
          .where((fixture) => _competitionPhase(fixture.round) == 'ALTRO')
          .toList();

      print('');
      print('Riepilogo per fase:');

      _logPhaseSummary('Qualificazioni / Play-off', qualifyingFixtures);

      _logPhaseSummary('Fase principale', mainStageFixtures);

      if (otherFixtures.isNotEmpty) {
        _logPhaseSummary('Altre fasi / N.D.', otherFixtures);
      }

      if (mainStageFixtures.isNotEmpty) {
        print('');
        print('Qualità avversari fase principale:');

        for (final fixture in mainStageFixtures) {
          final opponentLeague = team.opponentLeagues[fixture.opponentId];

          final managedLeague = opponentLeague == null
              ? null
              : LeagueManager.findById(opponentLeague.leagueId);

          final leagueName = opponentLeague == null
              ? 'N/D'
              : opponentLeague.leagueName;

          final strength = managedLeague == null
              ? 'N/D (non calibrata)'
              : managedLeague.aiWeight.toStringAsFixed(2);

          print(
            '- ${fixture.opponentName} | '
            'campionato: $leagueName | '
            'forza: $strength | '
            'risultato: ${fixture.goalsFor}-${fixture.goalsAgainst} '
            '(${fixture.result})',
          );
        }
      }

      print('');
      print('Partite precedenti nella competizione:');

      for (final fixture in history.fixtures) {
        final venue = fixture.isHome ? 'CASA' : 'TRASFERTA';

        final round = fixture.round.isEmpty ? 'turno N/D' : fixture.round;

        print(
          '- ${fixture.date.toIso8601String()} | '
          '$venue | '
          'vs ${fixture.opponentName} | '
          '${fixture.goalsFor}-${fixture.goalsAgainst} '
          '(${fixture.result}) | '
          '$round',
        );
      }
    }
  }

  String _competitionPhase(String round) {
    final normalized = round.toLowerCase().trim();

    if (normalized.contains('qualifying') ||
        normalized.contains('play-off') ||
        normalized.contains('playoff')) {
      return 'QUALIFICAZIONE';
    }

    if (normalized.contains('league stage') ||
        normalized.contains('group stage') ||
        normalized.contains('round of 16') ||
        normalized.contains('round of 32') ||
        normalized.contains('quarter') ||
        normalized.contains('semi') ||
        normalized == 'final') {
      return 'FASE PRINCIPALE';
    }

    return 'ALTRO';
  }

  void _logPhaseSummary(String label, List<HistoricalFixtureSample> fixtures) {
    if (fixtures.isEmpty) {
      print('$label: 0 partite');
      return;
    }

    final wins = fixtures.where((f) => f.result == 'V').length;
    final draws = fixtures.where((f) => f.result == 'X').length;
    final losses = fixtures.where((f) => f.result == 'S').length;

    final goalsFor = fixtures.fold<int>(
      0,
      (sum, fixture) => sum + fixture.goalsFor,
    );

    final goalsAgainst = fixtures.fold<int>(
      0,
      (sum, fixture) => sum + fixture.goalsAgainst,
    );

    print(
      '$label: '
      '${fixtures.length} partite | '
      '${wins}V / ${draws}X / ${losses}S | '
      '$goalsFor-$goalsAgainst',
    );
  }
}

class DiegoAiCompetitionContextService {
  static const int _maxMainStageOpponentsPerTeam = 6;

  final HistoricalTeamService _historicalService;
  final TeamDataResolver _teamDataResolver;

  DiegoAiCompetitionContextService({
    HistoricalTeamService? historicalService,
    TeamDataResolver? teamDataResolver,
  }) : _historicalService = historicalService ?? HistoricalTeamService(),
       _teamDataResolver = teamDataResolver ?? TeamDataResolver();

  Future<DiegoCompetitionContext?> build({
    required MatchModel match,
    required MatchDossier dossier,
  }) async {
    final referenceDate = DateTime.tryParse(match.date);

    if (referenceDate == null || match.leagueId <= 0) {
      return null;
    }

    final seasons = _candidateSeasons(
      match: match,
      referenceDate: referenceDate,
    );

    final results = await Future.wait([
      _buildTeamContext(
        teamId: match.homeTeamId,
        teamName: match.homeTeam,
        domesticLeagueId: dossier.homeCurrentLeagueId,
        domesticLeagueName: dossier.homeCurrentLeague,
        match: match,
        referenceDate: referenceDate,
        candidateSeasons: seasons,
      ),
      _buildTeamContext(
        teamId: match.awayTeamId,
        teamName: match.awayTeam,
        domesticLeagueId: dossier.awayCurrentLeagueId,
        domesticLeagueName: dossier.awayCurrentLeague,
        match: match,
        referenceDate: referenceDate,
        candidateSeasons: seasons,
      ),
    ]);

    return DiegoCompetitionContext(
      competitionId: match.leagueId,
      competitionName: match.league,
      referenceDate: referenceDate,
      home: results[0],
      away: results[1],
    );
  }

  Future<DiegoCompetitionTeamContext> _buildTeamContext({
    required int teamId,
    required String teamName,
    required int domesticLeagueId,
    required String domesticLeagueName,
    required MatchModel match,
    required DateTime referenceDate,
    required List<int> candidateSeasons,
  }) async {
    HistoricalTeamData? competitionHistory;
    int? competitionSeason;

    for (final season in candidateSeasons) {
      final history = await _historicalService.getHistoricalData(
        teamId: teamId,
        teamName: teamName,
        season: season,
        leagueId: match.leagueId,
        referenceDate: referenceDate,
        leagueName: match.league,
      );

      if (history != null && history.matchesPlayed > 0) {
        competitionHistory = history;
        competitionSeason = season;
        break;
      }
    }

    final opponentLeagues = <int, ResolvedTeamLeague>{};
    final attemptedOpponentIds = <int>{};

    if (competitionHistory != null) {
      for (final fixture in competitionHistory.fixtures) {
        if (!_isMainStageRound(fixture.round)) {
          continue;
        }

        final opponentId = fixture.opponentId;

        if (opponentId <= 0 || attemptedOpponentIds.contains(opponentId)) {
          continue;
        }

        if (attemptedOpponentIds.length >= _maxMainStageOpponentsPerTeam) {
          break;
        }

        attemptedOpponentIds.add(opponentId);

        final resolvedLeague = await _teamDataResolver.resolveCurrentLeagueOnly(
          teamId: opponentId,
          teamName: fixture.opponentName,
          referenceDate: referenceDate,
        );

        if (resolvedLeague != null) {
          opponentLeagues[opponentId] = resolvedLeague;
        }
      }
    }

    final knownDomesticLeague =
        LeagueManager.findById(domesticLeagueId) != null;

    return DiegoCompetitionTeamContext(
      teamId: teamId,
      teamName: teamName,
      domesticLeagueId: domesticLeagueId,
      domesticLeagueName: domesticLeagueName,
      domesticLeagueWeight: LeagueManager.getAiWeight(domesticLeagueId),
      domesticLeagueWeightIsFallback: !knownDomesticLeague,
      competitionSeason: competitionSeason,
      competitionHistory: competitionHistory,
      opponentLeagues: opponentLeagues,
    );
  }

  bool _isMainStageRound(String round) {
    final normalized = round.toLowerCase().trim();

    return normalized.contains('league stage') ||
        normalized.contains('group stage') ||
        normalized.contains('round of 16') ||
        normalized.contains('round of 32') ||
        normalized.contains('quarter') ||
        normalized.contains('semi') ||
        normalized == 'final';
  }

  List<int> _candidateSeasons({
    required MatchModel match,
    required DateTime referenceDate,
  }) {
    final year = referenceDate.year;

    // Le competizioni UEFA che attraversano due anni vengono
    // normalmente identificate dalla stagione di inizio.
    //
    // Esempio:
    // febbraio 2027 -> stagione 2026/27 -> proviamo prima 2026.
    if (match.isEuropeanCup && referenceDate.month <= 6) {
      return [year - 1, year];
    }

    return [year, year - 1];
  }
}
