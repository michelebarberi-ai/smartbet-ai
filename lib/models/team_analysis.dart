class TeamAnalysis {
  final String teamName;

  // Valori da 0 a 100
  final int form;
  final int attack;
  final int defense;
  final int homeAway;
  final int motivation;

  // Punteggio finale della squadra
  final int teamScore;

  const TeamAnalysis({
    required this.teamName,
    required this.form,
    required this.attack,
    required this.defense,
    required this.homeAway,
    required this.motivation,
    required this.teamScore,
  });
}
