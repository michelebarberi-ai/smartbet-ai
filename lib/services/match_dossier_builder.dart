import '../models/match_dossier.dart';
import '../models/match_model.dart';
import 'context_researcher.dart';
import 'team_data_resolver.dart';

class MatchDossierBuilder {
  final TeamDataResolver _resolver;
  final ContextResearcher _contextResearcher;

  MatchDossierBuilder({
    TeamDataResolver? resolver,
    ContextResearcher? contextResearcher,
  }) : _resolver = resolver ?? TeamDataResolver(),
       _contextResearcher = contextResearcher ?? ContextResearcher();

  // ============================================================
  // COSTRUZIONE DOSSIER
  // ============================================================

  Future<MatchDossier?> build(MatchModel match) async {
    print('');
    print('========================================');
    print('SMARTBET - MATCH DOSSIER BUILDER');
    print('========================================');
    print('Partita: ${match.homeTeam} - ${match.awayTeam}');
    print('Home ID: ${match.homeTeamId}');
    print('Away ID: ${match.awayTeamId}');

    // ----------------------------------------------------------
    // CONTROLLO ID
    // ----------------------------------------------------------

    if (!match.hasTeamIds) {
      print('ERRORE: ID squadre non disponibili');
      return null;
    }

    // ----------------------------------------------------------
    // DATA DI RIFERIMENTO
    // ----------------------------------------------------------

    final referenceDate = DateTime.tryParse(match.date);

    if (referenceDate == null) {
      print('ERRORE: data partita non valida');
      return null;
    }

    // ----------------------------------------------------------
    // DATI CASA
    // ----------------------------------------------------------

    print('');
    print('RECUPERO DATI CASA');

    final home = await _resolver.resolveTeam(
      teamId: match.homeTeamId,
      teamName: match.homeTeam,
      referenceDate: referenceDate,
    );

    // ----------------------------------------------------------
    // DATI OSPITE
    // ----------------------------------------------------------

    print('');
    print('RECUPERO DATI OSPITE');

    final away = await _resolver.resolveTeam(
      teamId: match.awayTeamId,
      teamName: match.awayTeam,
      referenceDate: referenceDate,
    );

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

    // ----------------------------------------------------------
    // CONTEXT RESEARCHER
    // ----------------------------------------------------------

    print('');
    print('========================================');
    print('RECUPERO CONTESTO PARTITA');
    print('========================================');

    final context = await _contextResearcher.research(match);

    // ----------------------------------------------------------
    // STATISTICHE CASA
    // ----------------------------------------------------------

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

    // ----------------------------------------------------------
    // RENDIMENTO CASA
    // ----------------------------------------------------------

    final homeVenue = <String, dynamic>{
      'matches': home.homeMatches,
      'wins': home.homeWins,
      'draws': home.homeDraws,
      'losses': home.homeLosses,
      'winRate': home.homeWinRate,
    };

    // ----------------------------------------------------------
    // STATISTICHE OSPITE
    // ----------------------------------------------------------

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

    // ----------------------------------------------------------
    // RENDIMENTO TRASFERTA
    // ----------------------------------------------------------

    final awayVenue = <String, dynamic>{
      'matches': away.awayMatches,
      'wins': away.awayWins,
      'draws': away.awayDraws,
      'losses': away.awayLosses,
      'winRate': away.awayWinRate,
    };

    // ----------------------------------------------------------
    // FORMA
    // ----------------------------------------------------------

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

    // ----------------------------------------------------------
    // ASSENZE
    // ----------------------------------------------------------

    final injuries = <String>[];

    for (final item in context.injuriesHome) {
      injuries.add('${match.homeTeam}: $item');
    }

    for (final item in context.injuriesAway) {
      injuries.add('${match.awayTeam}: $item');
    }

    // ----------------------------------------------------------
    // FORMAZIONI
    // ----------------------------------------------------------

    final probableLineups = <String>[];

    if (context.probableLineupsHome.isNotEmpty) {
      probableLineups.add('--- ${match.homeTeam} ---');

      probableLineups.addAll(context.probableLineupsHome);
    }

    if (context.probableLineupsAway.isNotEmpty) {
      probableLineups.add('--- ${match.awayTeam} ---');

      probableLineups.addAll(context.probableLineupsAway);
    }

    // ----------------------------------------------------------
    // H2H
    // ----------------------------------------------------------

    final headToHead = List<String>.from(context.headToHead);

    // ----------------------------------------------------------
    // CAMPI WEB / AI
    // ----------------------------------------------------------

    final news = <String>[];
    final suspensions = <String>[];
    final marketInformation = <String>[];

    // ----------------------------------------------------------
    // CONFIDENCE STATISTICA
    // ----------------------------------------------------------

    final statisticsConfidence =
        (((home.confidence + away.confidence) / 2) * 100).round().clamp(0, 100);

    // ----------------------------------------------------------
    // CONFIDENCE CONTESTO
    // ----------------------------------------------------------

    final contextConfidence = context.confidence;

    // ----------------------------------------------------------
    // CONFIDENCE DOSSIER
    // ----------------------------------------------------------

    final dossierConfidence =
        ((statisticsConfidence * 0.70) + (contextConfidence * 0.30))
            .round()
            .clamp(0, 100);

    // ----------------------------------------------------------
    // CREAZIONE DOSSIER
    // ----------------------------------------------------------

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

      // ========================================================
      // CATEGORIA ATTUALE
      // ========================================================
      homeCurrentLeague: home.currentLeagueName,

      homeCurrentLeagueId: home.currentLeagueId,

      awayCurrentLeague: away.currentLeagueName,

      awayCurrentLeagueId: away.currentLeagueId,

      // ========================================================
      // DATI
      // ========================================================
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

    // ----------------------------------------------------------
    // LOG
    // ----------------------------------------------------------

    print('');
    print('========================================');
    print('MATCH DOSSIER CREATO');
    print('========================================');

    print(
      'Partita: '
      '${dossier.homeTeam} - ${dossier.awayTeam}',
    );

    print('');

    // ==========================================================
    // CATEGORIE ATTUALI
    // ==========================================================

    print('CATEGORIA ATTUALE CASA:');
    print(
      '${home.currentLeagueSeason} - '
      '${home.currentLeagueName} '
      '(ID ${home.currentLeagueId})',
    );

    print('');

    print('FONTE STATISTICHE CASA:');
    print(
      '${home.season} - '
      '${home.leagueName} '
      '(ID ${home.leagueId})',
    );

    print('');

    print('CATEGORIA ATTUALE OSPITE:');
    print(
      '${away.currentLeagueSeason} - '
      '${away.currentLeagueName} '
      '(ID ${away.currentLeagueId})',
    );

    print('');

    print('FONTE STATISTICHE OSPITE:');
    print(
      '${away.season} - '
      '${away.leagueName} '
      '(ID ${away.leagueId})',
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

    print('');

    print(
      'Fonte casa: '
      '${home.dataSource}',
    );

    print(
      'Fonte ospite: '
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
  }
}
