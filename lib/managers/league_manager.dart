class LeagueInfo {
  final int id;
  final String name;
  final String country;
  final String countryCode;
  final LeagueType type;
  final double aiWeight;

  const LeagueInfo({
    required this.id,
    required this.name,
    required this.country,
    required this.countryCode,
    required this.type,
    required this.aiWeight,
  });

  bool get isEuropeanCup {
    return type == LeagueType.europeanCup;
  }

  bool get isFriendly {
    return type == LeagueType.friendly;
  }

  bool get isNationalCompetition {
    return type == LeagueType.national;
  }
}

enum LeagueType { domestic, domesticCup, europeanCup, friendly, national }

class LeagueManager {
  static const List<LeagueInfo> leagues = [
    // ==================================================
    // 🇮🇹 ITALIA
    // ==================================================
    LeagueInfo(
      id: 135,
      name: "Serie A",
      country: "Italia",
      countryCode: "IT",
      type: LeagueType.domestic,
      aiWeight: 1.00,
    ),

    LeagueInfo(
      id: 136,
      name: "Serie B",
      country: "Italia",
      countryCode: "IT",
      type: LeagueType.domestic,
      aiWeight: 0.95,
    ),

    LeagueInfo(
      id: 137,
      name: "Coppa Italia",
      country: "Italia",
      countryCode: "IT",
      type: LeagueType.domesticCup,
      aiWeight: 0.90,
    ),

    // ==================================================
    // 🏴 INGHILTERRA
    // ==================================================
    LeagueInfo(
      id: 39,
      name: "Premier League",
      country: "Inghilterra",
      countryCode: "GB",
      type: LeagueType.domestic,
      aiWeight: 1.00,
    ),

    LeagueInfo(
      id: 40,
      name: "Championship",
      country: "Inghilterra",
      countryCode: "GB",
      type: LeagueType.domestic,
      aiWeight: 0.95,
    ),

    LeagueInfo(
      id: 45,
      name: "FA Cup",
      country: "Inghilterra",
      countryCode: "GB",
      type: LeagueType.domesticCup,
      aiWeight: 0.90,
    ),

    LeagueInfo(
      id: 48,
      name: "League Cup",
      country: "Inghilterra",
      countryCode: "GB",
      type: LeagueType.domesticCup,
      aiWeight: 0.90,
    ),

    // ==================================================
    // 🇪🇸 SPAGNA
    // ==================================================
    LeagueInfo(
      id: 140,
      name: "La Liga",
      country: "Spagna",
      countryCode: "ES",
      type: LeagueType.domestic,
      aiWeight: 1.00,
    ),

    LeagueInfo(
      id: 141,
      name: "Segunda Division",
      country: "Spagna",
      countryCode: "ES",
      type: LeagueType.domestic,
      aiWeight: 0.95,
    ),

    LeagueInfo(
      id: 143,
      name: "Copa del Rey",
      country: "Spagna",
      countryCode: "ES",
      type: LeagueType.domesticCup,
      aiWeight: 0.90,
    ),

    // ==================================================
    // 🇩🇪 GERMANIA
    // ==================================================
    LeagueInfo(
      id: 78,
      name: "Bundesliga",
      country: "Germania",
      countryCode: "DE",
      type: LeagueType.domestic,
      aiWeight: 1.00,
    ),

    LeagueInfo(
      id: 79,
      name: "2. Bundesliga",
      country: "Germania",
      countryCode: "DE",
      type: LeagueType.domestic,
      aiWeight: 0.95,
    ),

    LeagueInfo(
      id: 81,
      name: "DFB Pokal",
      country: "Germania",
      countryCode: "DE",
      type: LeagueType.domesticCup,
      aiWeight: 0.90,
    ),

    // ==================================================
    // 🇫🇷 FRANCIA
    // ==================================================
    LeagueInfo(
      id: 61,
      name: "Ligue 1",
      country: "Francia",
      countryCode: "FR",
      type: LeagueType.domestic,
      aiWeight: 1.00,
    ),

    LeagueInfo(
      id: 62,
      name: "Ligue 2",
      country: "Francia",
      countryCode: "FR",
      type: LeagueType.domestic,
      aiWeight: 0.95,
    ),

    LeagueInfo(
      id: 66,
      name: "Coupe de France",
      country: "Francia",
      countryCode: "FR",
      type: LeagueType.domesticCup,
      aiWeight: 0.90,
    ),

    // ==================================================
    // 🇳🇱 OLANDA
    // ==================================================
    LeagueInfo(
      id: 88,
      name: "Eredivisie",
      country: "Olanda",
      countryCode: "NL",
      type: LeagueType.domestic,
      aiWeight: 1.00,
    ),

    // ==================================================
    // 🇵🇹 PORTOGALLO
    // ==================================================
    LeagueInfo(
      id: 94,
      name: "Primeira Liga",
      country: "Portogallo",
      countryCode: "PT",
      type: LeagueType.domestic,
      aiWeight: 1.00,
    ),

    // ==================================================
    // 🇧🇪 BELGIO
    // ==================================================
    LeagueInfo(
      id: 144,
      name: "Jupiler Pro League",
      country: "Belgio",
      countryCode: "BE",
      type: LeagueType.domestic,
      aiWeight: 0.95,
    ),

    // ==================================================
    // 🇹🇷 TURCHIA
    // ==================================================
    LeagueInfo(
      id: 203,
      name: "Super Lig",
      country: "Turchia",
      countryCode: "TR",
      type: LeagueType.domestic,
      aiWeight: 0.95,
    ),

    // ==================================================
    // 🏆 COPPE EUROPEE
    // ==================================================
    LeagueInfo(
      id: 2,
      name: "Champions League",
      country: "Europa",
      countryCode: "EU",
      type: LeagueType.europeanCup,
      aiWeight: 1.00,
    ),

    LeagueInfo(
      id: 3,
      name: "Europa League",
      country: "Europa",
      countryCode: "EU",
      type: LeagueType.europeanCup,
      aiWeight: 1.00,
    ),

    LeagueInfo(
      id: 848,
      name: "Conference League",
      country: "Europa",
      countryCode: "EU",
      type: LeagueType.europeanCup,
      aiWeight: 0.90,
    ),
  ];

  // ====================================================
  // TUTTE LE NAZIONI
  // ====================================================

  static List<String> get countries {
    final result = <String>[];

    for (final league in leagues) {
      if (!result.contains(league.country)) {
        result.add(league.country);
      }
    }

    return result;
  }

  // ====================================================
  // COMPETIZIONI DI UNA NAZIONE
  // ====================================================

  static List<LeagueInfo> byCountry(String country) {
    return leagues.where((league) => league.country == country).toList();
  }

  // ====================================================
  // SOLO CAMPIONATI
  // ====================================================

  static List<LeagueInfo> get domesticLeagues {
    return leagues
        .where((league) => league.type == LeagueType.domestic)
        .toList();
  }

  // ====================================================
  // COPPE NAZIONALI
  // ====================================================

  static List<LeagueInfo> get domesticCups {
    return leagues
        .where((league) => league.type == LeagueType.domesticCup)
        .toList();
  }

  // ====================================================
  // COPPE EUROPEE
  // ====================================================

  static List<LeagueInfo> get europeanCups {
    return leagues
        .where((league) => league.type == LeagueType.europeanCup)
        .toList();
  }

  // ====================================================
  // AMICHEVOLI
  // ====================================================

  static List<LeagueInfo> get friendlies {
    return leagues
        .where((league) => league.type == LeagueType.friendly)
        .toList();
  }

  // ====================================================
  // CERCA COMPETIZIONE
  // ====================================================

  static LeagueInfo? findById(int id) {
    for (final league in leagues) {
      if (league.id == id) {
        return league;
      }
    }

    return null;
  }

  // ====================================================
  // PESO AI
  // ====================================================

  static double getAiWeight(int leagueId) {
    final league = findById(leagueId);

    if (league == null) {
      return 0.70;
    }

    return league.aiWeight;
  }
}
