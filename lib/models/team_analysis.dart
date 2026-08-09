class TeamAnalysis {
  // ============================================================
  // DATI PRINCIPALI
  // ============================================================

  final String teamName;

  final int form;
  final int attack;
  final int defense;

  // ============================================================
  // DATI CASA / TRASFERTA
  // ============================================================

  final int homePerformance;
  final int awayPerformance;

  // ============================================================
  // DATI AGGIUNTIVI
  // ============================================================

  final int homeAway;
  final int motivation;

  final int matchesPlayed;

  // ============================================================
  // COSTRUTTORE
  // ============================================================

  const TeamAnalysis({
    this.teamName = '',

    this.form = 0,
    this.attack = 0,
    this.defense = 0,

    this.homePerformance = 0,
    this.awayPerformance = 0,

    this.homeAway = 0,
    this.motivation = 0,

    this.matchesPlayed = 0,
  });

  // ============================================================
  // PUNTEGGIO COMPLESSIVO
  // ============================================================

  double get totalScore {
    final base = (form + attack + defense) / 3.0;

    final venue = (homePerformance + awayPerformance) / 2.0;

    return (base * 0.75) + (venue * 0.25);
  }

  // ============================================================
  // DATI SUFFICIENTI
  // ============================================================

  bool get hasEnoughData {
    return matchesPlayed >= 3;
  }
}
