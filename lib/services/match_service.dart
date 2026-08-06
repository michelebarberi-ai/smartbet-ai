import '../models/match_model.dart';

class MatchService {
  static List<MatchModel> getTodayMatches() {
    return const [
      MatchModel(
        homeTeam: "Inter",
        awayTeam: "Milan",
        league: "Serie A",
        date: "Oggi • 20:45",
        smartScore: 91,
        homeWin: 49,
        draw: 31,
        awayWin: 20,
        valueBet: "Inter vincente",
        odd: 2.05,
      ),

      MatchModel(
        homeTeam: "Juventus",
        awayTeam: "Napoli",
        league: "Serie A",
        date: "Oggi • 18:00",
        smartScore: 84,
        homeWin: 42,
        draw: 30,
        awayWin: 28,
        valueBet: "Over 2.5",
        odd: 1.95,
      ),

      MatchModel(
        homeTeam: "Liverpool",
        awayTeam: "Arsenal",
        league: "Premier League",
        date: "Domani • 21:00",
        smartScore: 88,
        homeWin: 46,
        draw: 27,
        awayWin: 27,
        valueBet: "Gol/Gol",
        odd: 1.82,
      ),

      MatchModel(
        homeTeam: "Real Madrid",
        awayTeam: "Barcellona",
        league: "La Liga",
        date: "Domani • 21:00",
        smartScore: 93,
        homeWin: 54,
        draw: 23,
        awayWin: 23,
        valueBet: "Real Madrid",
        odd: 2.20,
      ),
    ];
  }
}
