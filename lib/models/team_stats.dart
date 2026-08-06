class TeamStats {
  final String teamName;

  // Ultime 5 partite
  final int winsLast5;
  final int drawsLast5;
  final int lossesLast5;

  // Gol
  final int goalsScored;
  final int goalsConceded;

  // Expected Goals
  final double xG;
  final double xGA;

  // Stato squadra
  final int injuredPlayers;
  final int suspendedPlayers;

  // Casa / Trasferta
  final bool homeMatch;

  // Classifica
  final int leaguePosition;

  // Forma (0-100)
  final int formScore;

  const TeamStats({
    required this.teamName,
    required this.winsLast5,
    required this.drawsLast5,
    required this.lossesLast5,
    required this.goalsScored,
    required this.goalsConceded,
    required this.xG,
    required this.xGA,
    required this.injuredPlayers,
    required this.suspendedPlayers,
    required this.homeMatch,
    required this.leaguePosition,
    required this.formScore,
  });
}
