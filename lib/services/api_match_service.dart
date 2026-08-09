import '../managers/league_manager.dart';
import '../models/match_model.dart';
import 'football_api_service.dart';

class ApiMatchService {
  final FootballApiService _api = FootballApiService();

  Future<List<MatchModel>> getTodayMatches() async {
    final response = await _api.getNextMatches();

    final matches = <MatchModel>[];

    for (final match in response) {
      final leagueData = match["league"] ?? {};

      final int leagueId = leagueData["id"] ?? 0;
      final String leagueName = leagueData["name"] ?? "";
      final String apiCountry = leagueData["country"] ?? "";

      // Cerchiamo la competizione nel nostro LeagueManager
      final leagueInfo = LeagueManager.findById(leagueId);

      String country = apiCountry;
      String countryCode = "";
      String leagueType = "domestic";

      bool isEuropeanCup = false;
      bool isFriendly = false;
      bool isNational = false;

      double aiWeight = 0.70;

      if (leagueInfo != null) {
        country = leagueInfo.country;
        countryCode = leagueInfo.countryCode;
        leagueType = leagueInfo.type.name;

        isEuropeanCup = leagueInfo.isEuropeanCup;
        isFriendly = leagueInfo.isFriendly;
        isNational = leagueInfo.isNationalCompetition;

        aiWeight = leagueInfo.aiWeight;
      } else {
        // Classificazione automatica delle competizioni
        final name = leagueName.toLowerCase();

        if (name.contains("friendly") ||
            name.contains("friendlies") ||
            name.contains("amical")) {
          isFriendly = true;
          leagueType = "friendly";
          aiWeight = 0.60;
        }

        if (name.contains("world cup") ||
            name.contains("euro") ||
            name.contains("nations league")) {
          isNational = true;
          leagueType = "national";
          aiWeight = 0.90;
        }

        if (apiCountry.toLowerCase() == "europe" ||
            name.contains("champions league") ||
            name.contains("europa league") ||
            name.contains("conference league")) {
          isEuropeanCup = true;
          leagueType = "europeanCup";
          aiWeight = 0.90;
          country = "Europa";
          countryCode = "EU";
        }
      }

      matches.add(
        MatchModel.fromApi(
          match,
          country: country,
          countryCode: countryCode,
          leagueType: leagueType,
          isEuropeanCup: isEuropeanCup,
          isFriendly: isFriendly,
          isNational: isNational,
          aiWeight: aiWeight,
        ),
      );
    }

    return matches;
  }
}
