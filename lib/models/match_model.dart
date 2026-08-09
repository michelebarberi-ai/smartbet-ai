class MatchModel {
  // ============================================================
  // IDENTIFICATIVI
  // ============================================================

  final int fixtureId;

  final int homeTeamId;
  final int awayTeamId;

  // ============================================================
  // SQUADRE
  // ============================================================

  final String homeTeam;
  final String awayTeam;

  // ============================================================
  // COMPETIZIONE
  // ============================================================

  final String league;
  final int leagueId;

  final String country;
  final String countryCode;

  final String date;

  final String leagueType;

  final bool isEuropeanCup;
  final bool isFriendly;
  final bool isNational;

  // ============================================================
  // PESO AI
  // ============================================================

  final double aiWeight;

  // ============================================================
  // DATI AI
  // ============================================================

  int smartScore;

  int homeWin;
  int draw;
  int awayWin;

  String valueBet;
  double odd;

  // ============================================================
  // COSTRUTTORE
  // ============================================================

  MatchModel({
    required this.fixtureId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    required this.leagueId,
    required this.country,
    required this.countryCode,
    required this.date,
    required this.leagueType,
    required this.isEuropeanCup,
    required this.isFriendly,
    required this.isNational,
    required this.aiWeight,
    required this.smartScore,
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.valueBet,
    required this.odd,
  });

  // ============================================================
  // CREAZIONE DA API-FOOTBALL
  // ============================================================

  factory MatchModel.fromApi(
    Map<String, dynamic> json, {
    String country = "",
    String countryCode = "",
    String leagueType = "domestic",
    bool isEuropeanCup = false,
    bool isFriendly = false,
    bool isNational = false,
    double aiWeight = 0.70,
  }) {
    final fixture = json["fixture"] ?? {};

    final teams = json["teams"] ?? {};

    final home = teams["home"] ?? {};

    final away = teams["away"] ?? {};

    final leagueData = json["league"] ?? {};

    return MatchModel(
      // ========================================================
      // FIXTURE
      // ========================================================
      fixtureId: fixture["id"] ?? 0,

      // ========================================================
      // ID SQUADRE
      // ========================================================
      homeTeamId: home["id"] ?? 0,

      awayTeamId: away["id"] ?? 0,

      // ========================================================
      // NOMI SQUADRE
      // ========================================================
      homeTeam: home["name"] ?? "",

      awayTeam: away["name"] ?? "",

      // ========================================================
      // COMPETIZIONE
      // ========================================================
      league: leagueData["name"] ?? "",

      leagueId: leagueData["id"] ?? 0,

      // ========================================================
      // NAZIONE
      // ========================================================
      country: country.isNotEmpty ? country : leagueData["country"] ?? "",

      countryCode: countryCode,

      // ========================================================
      // DATA
      // ========================================================
      date: fixture["date"] ?? "",

      // ========================================================
      // TIPO COMPETIZIONE
      // ========================================================
      leagueType: leagueType,

      isEuropeanCup: isEuropeanCup,

      isFriendly: isFriendly,

      isNational: isNational,

      // ========================================================
      // PESO AI
      // ========================================================
      aiWeight: aiWeight,

      // ========================================================
      // DATI AI
      // ========================================================
      smartScore: 0,

      homeWin: 0,

      draw: 0,

      awayWin: 0,

      valueBet: "",

      odd: 0,
    );
  }

  // ============================================================
  // NOME COMPETIZIONE
  // ============================================================

  String get competitionName {
    if (league.isEmpty) {
      return "Competizione sconosciuta";
    }

    return league;
  }

  // ============================================================
  // CATEGORIA
  // ============================================================

  String get category {
    if (isEuropeanCup) {
      return "Coppe Europee";
    }

    if (isNational) {
      return "Nazionali";
    }

    if (isFriendly) {
      return "Amichevoli";
    }

    if (country.isEmpty) {
      return "Altre";
    }

    return country;
  }

  // ============================================================
  // CONTROLLO ID SQUADRE
  // ============================================================

  bool get hasTeamIds {
    return homeTeamId > 0 && awayTeamId > 0;
  }
}
