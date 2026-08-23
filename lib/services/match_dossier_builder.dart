import '../models/match_dossier.dart';
import '../models/match_model.dart';
import 'context_researcher.dart';
import 'football_data_service.dart';
import 'team_data_resolver.dart';

class MatchDossierBuilder {
  final TeamDataResolver _resolver;
  final ContextResearcher _contextResearcher;
  final FootballDataService _footballDataService;

  MatchDossierBuilder({
    TeamDataResolver? resolver,
    ContextResearcher? contextResearcher,
    FootballDataService? footballDataService,
  }) : _resolver = resolver ?? TeamDataResolver(),
       _contextResearcher = contextResearcher ?? ContextResearcher(),
       _footballDataService = footballDataService ?? FootballDataService();

  // ============================================================
  // COSTRUZIONE DOSSIER
  // ============================================================

  Future<MatchDossier?> build(MatchModel match) async {
    print('');
    print('========================================');
    print('SMARTBET - MATCH DOSSIER BUILDER');
    print('========================================');
    print(
      'Partita: '
      '${match.homeTeam} - '
      '${match.awayTeam}',
    );
    print('Home ID: ${match.homeTeamId}');
    print('Away ID: ${match.awayTeamId}');

    if (!match.hasTeamIds) {
      print('ERRORE: ID squadre non disponibili');
      return null;
    }

    // ==========================================================
    // DATI STATISTICI PRINCIPALI
    // ==========================================================
    //
    // Le due squadre vengono risolte in parallelo.
    // ==========================================================

    print('');
    print('RECUPERO DATI STATISTICI SQUADRE');

    final referenceDate = DateTime.tryParse(match.date);

    if (referenceDate == null) {
      print('ERRORE: data partita non valida');
      return null;
    }

    final homeFuture = _resolver.resolveTeam(
      teamId: match.homeTeamId,
      teamName: match.homeTeam,
      referenceDate: referenceDate,
    );

    final awayFuture = _resolver.resolveTeam(
      teamId: match.awayTeamId,
      teamName: match.awayTeam,
      referenceDate: referenceDate,
    );

    final home = await homeFuture;
    final away = await awayFuture;

    if (home == null || away == null) {
      print('');
      print('DOSSIER NON DISPONIBILE');

      if (home == null) {
        print('Dati casa mancanti');
      }

      if (away == null) {
        print('Dati ospite mancanti');
      }

      return null;
    }

    // ==========================================================
    // CONTESTO + FONTE SECONDARIA
    // ==========================================================
    //
    // API-Football continua ad essere la fonte strutturata
    // principale.
    //
    // football-data.org viene usata come controllo indipendente
    // della fixture e, quando disponibile nel piano gratuito,
    // della classifica corrente.
    //
    // I due recuperi avvengono in parallelo.
    // ==========================================================

    print('');
    print('========================================');
    print('RECUPERO CONTESTO MULTI-SOURCE');
    print('========================================');

    final contextFuture = _contextResearcher.research(match);

    final secondaryFuture = _footballDataService.research(match);

    final context = await contextFuture;

    final secondary = await secondaryFuture;

    // ==========================================================
    // STATISTICHE CASA
    // ==========================================================

    final homeStatistics = <String, dynamic>{
      'season': home.season,
      'leagueId': home.leagueId,
      'leagueName': home.leagueName,
      'matchesPlayed': home.matchesPlayed,
      'wins': home.wins,
      'draws': home.draws,
      'losses': home.losses,
      'goalsFor': home.goalsFor,
      'goalsAgainst': home.goalsAgainst,
      'winRate': home.winRate,
      'goalsPerMatch': home.goalsPerMatch,
      'concededPerMatch': home.concededPerMatch,
      'goalDifferencePerMatch': home.goalDifferencePerMatch,
      'confidence': home.confidence,
      'dataSource': home.dataSource,
      'sourceTeam': home.sourceTeamName,
    };

    final homeVenue = <String, dynamic>{
      'matches': home.homeMatches,
      'wins': home.homeWins,
      'draws': home.homeDraws,
      'losses': home.homeLosses,
      'winRate': home.homeWinRate,
    };

    // ==========================================================
    // STATISTICHE OSPITE
    // ==========================================================

    final awayStatistics = <String, dynamic>{
      'season': away.season,
      'leagueId': away.leagueId,
      'leagueName': away.leagueName,
      'matchesPlayed': away.matchesPlayed,
      'wins': away.wins,
      'draws': away.draws,
      'losses': away.losses,
      'goalsFor': away.goalsFor,
      'goalsAgainst': away.goalsAgainst,
      'winRate': away.winRate,
      'goalsPerMatch': away.goalsPerMatch,
      'concededPerMatch': away.concededPerMatch,
      'goalDifferencePerMatch': away.goalDifferencePerMatch,
      'confidence': away.confidence,
      'dataSource': away.dataSource,
      'sourceTeam': away.sourceTeamName,
    };

    final awayVenue = <String, dynamic>{
      'matches': away.awayMatches,
      'wins': away.awayWins,
      'draws': away.awayDraws,
      'losses': away.awayLosses,
      'winRate': away.awayWinRate,
    };

    // ==========================================================
    // FORMA
    // ==========================================================

    final homeForm = <String, dynamic>{
      'available': context.recentMatchesHome.isNotEmpty,
      'matches': context.recentMatchesHome,
      'count': context.recentMatchesHome.length,
    };

    final awayForm = <String, dynamic>{
      'available': context.recentMatchesAway.isNotEmpty,
      'matches': context.recentMatchesAway,
      'count': context.recentMatchesAway.length,
    };

    // ==========================================================
    // ASSENZE
    // ==========================================================

    final injuries = <String>[];

    for (final item in context.injuriesHome) {
      injuries.add('${match.homeTeam}: $item');
    }

    for (final item in context.injuriesAway) {
      injuries.add('${match.awayTeam}: $item');
    }

    // ==========================================================
    // FORMAZIONI
    // ==========================================================

    final probableLineups = <String>[];

    if (context.probableLineupsHome.isNotEmpty) {
      probableLineups.add('--- ${match.homeTeam} ---');

      probableLineups.addAll(context.probableLineupsHome);
    }

    if (context.probableLineupsAway.isNotEmpty) {
      probableLineups.add('--- ${match.awayTeam} ---');

      probableLineups.addAll(context.probableLineupsAway);
    }

    final headToHead = List<String>.from(context.headToHead);

    // ==========================================================
    // CAMPI WEB / AI / MULTI-SOURCE
    // ==========================================================
    //
    // Le news restano demandate alla ricerca web del backend AI.
    //
    // marketInformation viene usato anche come contenitore
    // compatibile per il controllo statistico indipendente
    // football-data.org, senza modificare il modello esistente.
    // ==========================================================

    final news = <String>[];
    final suspensions = <String>[];

    final marketInformation = <String>[...secondary.dossierLines];

    // ==========================================================
    // CONFIDENCE STATISTICA PRINCIPALE
    // ==========================================================

    final statisticsConfidence =
        (((home.confidence + away.confidence) / 2) * 100).round().clamp(0, 100);

    final contextConfidence = context.confidence;

    // ==========================================================
    // CONFIDENCE DOSSIER MULTI-SOURCE
    // ==========================================================
    //
    // Se football-data.org non copre la gara, manteniamo
    // esattamente la vecchia formula 70/30.
    //
    // Se la fonte secondaria è disponibile, assegniamo:
    // - 60% statistiche principali
    // - 25% contesto API-Football
    // - 15% controllo indipendente
    //
    // In questo modo la seconda fonte rafforza la qualità dati,
    // ma non può da sola ribaltare l'analisi.
    // ==========================================================

    final dossierConfidence = secondary.available
        ? ((statisticsConfidence * 0.60) +
                  (contextConfidence * 0.25) +
                  (secondary.confidence * 0.15))
              .round()
              .clamp(0, 100)
        : ((statisticsConfidence * 0.70) + (contextConfidence * 0.30))
              .round()
              .clamp(0, 100);

    // ==========================================================
    // CREAZIONE DOSSIER
    // ==========================================================

    final dossier = MatchDossier(
      fixtureId: match.fixtureId,
      homeTeam: match.homeTeam,
      awayTeam: match.awayTeam,
      homeTeamId: match.homeTeamId,
      awayTeamId: match.awayTeamId,
      matchDate: match.date,
      competition: match.league,
      competitionId: match.leagueId,
      country: match.country,
      homeCurrentLeague: match.league,
      homeCurrentLeagueId: match.leagueId,
      awayCurrentLeague: match.league,
      awayCurrentLeagueId: match.leagueId,
      homeStatistics: homeStatistics,
      homeForm: homeForm,
      homeVenue: homeVenue,
      awayStatistics: awayStatistics,
      awayForm: awayForm,
      awayVenue: awayVenue,
      news: news,
      injuries: injuries,
      suspensions: suspensions,
      probableLineups: probableLineups,
      marketInformation: marketInformation,
      headToHead: headToHead,
      dataConfidence: dossierConfidence,
      preMatchOnly: true,
    );

    // ==========================================================
    // LOG
    // ==========================================================

    print('');
    print('========================================');
    print('MATCH DOSSIER MULTI-SOURCE CREATO');
    print('========================================');

    print(
      'Partita: '
      '${dossier.homeTeam} - '
      '${dossier.awayTeam}',
    );

    print('');
    print(
      'Confidence statistiche: '
      '$statisticsConfidence%',
    );
    print(
      'Confidence contesto: '
      '$contextConfidence%',
    );

    print(
      'football-data.org: '
      '${secondary.available ? "DISPONIBILE" : "NON DISPONIBILE"}',
    );

    if (secondary.available) {
      print(
        'Confidence fonte secondaria: '
        '${secondary.confidence}%',
      );

      print(
        'Classifica secondaria: '
        '${secondary.hasStandings ? "SI" : "NO"}',
      );

      print(
        'Competizione secondaria: '
        '${secondary.competition}',
      );
    }

    print(
      'Confidence dossier: '
      '${dossier.dataConfidence}%',
    );

    print('');
    print(
      'Forma casa: '
      '${context.recentMatchesHome.length}',
    );
    print(
      'Forma ospite: '
      '${context.recentMatchesAway.length}',
    );
    print(
      'H2H: '
      '${context.headToHead.length}',
    );
    print(
      'Assenze: '
      '${injuries.length}',
    );
    print(
      'Dati formazione: '
      '${probableLineups.length}',
    );
    print(
      'Dati fonte secondaria: '
      '${marketInformation.length}',
    );

    print('');
    print(
      'Fonte principale casa: '
      '${home.dataSource}',
    );
    print(
      'Fonte principale ospite: '
      '${away.dataSource}',
    );

    print('========================================');

    return dossier;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _resolver.dispose();
    _contextResearcher.dispose();
    _footballDataService.dispose();
  }
}
