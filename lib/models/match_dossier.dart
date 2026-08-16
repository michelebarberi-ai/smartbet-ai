class MatchDossier {
  // ============================================================
  // PARTITA
  // ============================================================

  final int fixtureId;

  final String homeTeam;
  final String awayTeam;

  final int homeTeamId;
  final int awayTeamId;

  final String matchDate;

  final String competition;
  final int competitionId;

  final String country;

  // ============================================================
  // CATEGORIA ATTUALE
  // ============================================================
  //
  // IMPORTANTE:
  // Questi campi rappresentano il campionato ATTUALE
  // delle due squadre.
  //
  // NON devono essere confusi con il campionato da cui
  // provengono le statistiche storiche.
  //
  // Esempio:
  //
  // Arezzo:
  // currentLeague = Serie B
  //
  // mentre:
  //
  // statisticsSourceLeague = Serie C - Girone B
  //
  // se le statistiche utilizzate provengono dal 2025.
  // ============================================================

  final String homeCurrentLeague;
  final int homeCurrentLeagueId;

  final String awayCurrentLeague;
  final int awayCurrentLeagueId;

  // ============================================================
  // DATI CASA
  // ============================================================

  final Map<String, dynamic> homeStatistics;

  final Map<String, dynamic> homeForm;

  final Map<String, dynamic> homeVenue;

  // ============================================================
  // DATI OSPITE
  // ============================================================

  final Map<String, dynamic> awayStatistics;

  final Map<String, dynamic> awayForm;

  final Map<String, dynamic> awayVenue;

  // ============================================================
  // CONTESTO
  // ============================================================

  final List<String> news;

  final List<String> injuries;

  final List<String> suspensions;

  final List<String> probableLineups;

  final List<String> marketInformation;

  final List<String> headToHead;

  // ============================================================
  // QUALITÀ DATI
  // ============================================================

  final int dataConfidence;

  final bool preMatchOnly;

  // ============================================================
  // COSTRUTTORE
  // ============================================================

  const MatchDossier({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.matchDate,
    required this.competition,
    required this.competitionId,
    required this.country,

    // Categoria attuale
    required this.homeCurrentLeague,
    required this.homeCurrentLeagueId,
    required this.awayCurrentLeague,
    required this.awayCurrentLeagueId,

    // Casa
    required this.homeStatistics,
    required this.homeForm,
    required this.homeVenue,

    // Ospite
    required this.awayStatistics,
    required this.awayForm,
    required this.awayVenue,

    // Contesto
    required this.news,
    required this.injuries,
    required this.suspensions,
    required this.probableLineups,
    required this.marketInformation,
    required this.headToHead,

    // Qualità
    required this.dataConfidence,
    required this.preMatchOnly,
  });

  // ============================================================
  // CONVERSIONE JSON
  // ============================================================

  Map<String, dynamic> toJson() {
    return {
      "fixture": {
        "id": fixtureId,
        "homeTeam": homeTeam,
        "awayTeam": awayTeam,
        "homeTeamId": homeTeamId,
        "awayTeamId": awayTeamId,
        "matchDate": matchDate,
        "competition": competition,
        "competitionId": competitionId,
        "country": country,
      },

      // ========================================================
      // SQUADRA CASA
      // ========================================================
      "homeTeam": {
        "currentCompetition": {
          "leagueId": homeCurrentLeagueId,
          "leagueName": homeCurrentLeague,
        },

        "statistics": homeStatistics,

        "statisticsSource": {
          "season": homeStatistics["season"],
          "leagueId": homeStatistics["leagueId"],
          "leagueName": homeStatistics["leagueName"],
          "dataSource": homeStatistics["dataSource"],
        },

        "form": homeForm,
        "venue": homeVenue,
      },

      // ========================================================
      // SQUADRA OSPITE
      // ========================================================
      "awayTeam": {
        "currentCompetition": {
          "leagueId": awayCurrentLeagueId,
          "leagueName": awayCurrentLeague,
        },

        "statistics": awayStatistics,

        "statisticsSource": {
          "season": awayStatistics["season"],
          "leagueId": awayStatistics["leagueId"],
          "leagueName": awayStatistics["leagueName"],
          "dataSource": awayStatistics["dataSource"],
        },

        "form": awayForm,
        "venue": awayVenue,
      },

      // ========================================================
      // CONTESTO
      // ========================================================
      "context": {
        "news": news,
        "injuries": injuries,
        "suspensions": suspensions,
        "probableLineups": probableLineups,
        "marketInformation": marketInformation,
        "headToHead": headToHead,
      },

      // ========================================================
      // GERARCHIA FONTI
      // ========================================================
      "sourcePolicy": {
        "fixtureAuthority": "API-Football",
        "currentCompetitionAuthority": "API-Football",
        "statisticsAuthority": "API-Football",
        "webRole": "context_only",

        "rules": [
          "Fixture, squadre, data e competizione confermate da API-Football hanno priorità.",
          "La categoria attuale della squadra non deve essere dedotta dalla stagione statistica utilizzata.",
          "Il campionato delle statistiche indica esclusivamente la fonte del campione statistico.",
          "Le informazioni web possono integrare news, allenatore, trasferimenti, motivazioni e indisponibili.",
          "Le informazioni web non devono sovrascrivere fixture, squadre o competizione corrente confermate dall'API.",
        ],
      },

      // ========================================================
      // QUALITÀ DATI
      // ========================================================
      "dataQuality": {
        "confidence": dataConfidence,
        "preMatchOnly": preMatchOnly,
      },
    };
  }
}
