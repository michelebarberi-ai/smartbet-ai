class MatchModel {
  final String homeTeam;
  final String awayTeam;
  final String league;
  final String date;

  // Smart Score™ calcolato da SmartCore
  final int smartScore;

  // Probabilità
  final int homeWin;
  final int draw;
  final int awayWin;

  // Pronostico consigliato
  final String valueBet;
  final double odd;

  const MatchModel({
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    required this.date,
    required this.smartScore,
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.valueBet,
    required this.odd,
  });
}
