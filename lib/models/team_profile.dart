class TeamProfile {
  // ============================================================
  // IDENTITÀ
  // ============================================================

  final int teamId;
  final String teamName;
  final String country;
  final String league;

  // ============================================================
  // FORZA SQUADRA
  // ============================================================

  final int strength;
  final int squadStrength;
  final int attackStrength;
  final int defenseStrength;

  // ============================================================
  // PRESTAZIONI
  // ============================================================

  final int form;
  final int homeStrength;
  final int awayStrength;

  // ============================================================
  // STORICO / COMPETIZIONE
  // ============================================================

  final int historicalStrength;
  final int leagueStrength;

  // ============================================================
  // DISPONIBILITÀ
  // ============================================================

  final int injuredPlayers;
  final int suspendedPlayers;
  final int unavailablePlayers;

  // ============================================================
  // AFFIDABILITÀ DATI
  // ============================================================

  final int dataConfidence;

  // ============================================================
  // COSTRUTTORE
  // ============================================================

  const TeamProfile({
    required this.teamId,
    required this.teamName,
    this.country = '',
    this.league = '',
    this.strength = 50,
    this.squadStrength = 50,
    this.attackStrength = 50,
    this.defenseStrength = 50,
    this.form = 50,
    this.homeStrength = 50,
    this.awayStrength = 50,
    this.historicalStrength = 50,
    this.leagueStrength = 50,
    this.injuredPlayers = 0,
    this.suspendedPlayers = 0,
    this.unavailablePlayers = 0,
    this.dataConfidence = 0,
  });

  // ============================================================
  // NUMERO TOTALE ASSENTI
  // ============================================================

  int get totalUnavailable {
    return unavailablePlayers;
  }

  // ============================================================
  // DATI RECENTI DISPONIBILI
  // ============================================================

  bool get hasRecentData {
    return form > 0;
  }

  // ============================================================
  // PROFILO UTILIZZABILE
  // ============================================================

  bool get hasEnoughData {
    return dataConfidence >= 30;
  }
}
