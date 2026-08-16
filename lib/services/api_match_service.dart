import '../managers/league_manager.dart';
import '../models/match_model.dart';
import 'football_api_service.dart';

class ApiMatchService {
  final FootballApiService _api = FootballApiService();

  // ============================================================
  // PARTITE DI OGGI
  // ============================================================

  Future<List<MatchModel>> getTodayMatches() async {
    final response = await _api.getNextMatches();

    return _convertResponseToMatches(response);
  }

  // ============================================================
  // PARTITE PER DATA SPECIFICA
  // ============================================================

  Future<List<MatchModel>> getMatchesByDate(DateTime date) async {
    final response = await _api.getMatchesByDate(date);

    return _convertResponseToMatches(response);
  }

  // ============================================================
  // NORMALIZZAZIONE PAESE
  // ============================================================

  String _normalizeCountry(String value) {
    final country = value.trim();

    if (country.isEmpty) {
      return 'Internazionale';
    }

    const aliases = <String, String>{
      'Italy': 'Italia',
      'Italia': 'Italia',
      'England': 'Inghilterra',
      'United Kingdom': 'Inghilterra',
      'Spain': 'Spagna',
      'Germany': 'Germania',
      'France': 'Francia',
      'Netherlands': 'Paesi Bassi',
      'Holland': 'Paesi Bassi',
      'Portugal': 'Portogallo',
      'Belgium': 'Belgio',
      'Turkey': 'Turchia',
      'Türkiye': 'Turchia',
      'Brazil': 'Brasile',
      'Argentina': 'Argentina',
      'Mexico': 'Messico',
      'Japan': 'Giappone',
      'South Korea': 'Corea del Sud',
      'Korea Republic': 'Corea del Sud',
      'Australia': 'Australia',
      'Canada': 'Canada',
      'Greece': 'Grecia',
      'Switzerland': 'Svizzera',
      'Austria': 'Austria',
      'Denmark': 'Danimarca',
      'Sweden': 'Svezia',
      'Norway': 'Norvegia',
      'Finland': 'Finlandia',
      'Poland': 'Polonia',
      'Croatia': 'Croazia',
      'Serbia': 'Serbia',
      'Romania': 'Romania',
      'Ukraine': 'Ucraina',
      'Scotland': 'Scozia',
      'Ireland': 'Irlanda',
      'Northern Ireland': 'Irlanda del Nord',
      'Czech Republic': 'Repubblica Ceca',
      'Czechia': 'Repubblica Ceca',
      'Slovakia': 'Slovacchia',
      'Hungary': 'Ungheria',
      'Slovenia': 'Slovenia',
      'Bulgaria': 'Bulgaria',
      'Israel': 'Israele',
      'Saudi Arabia': 'Arabia Saudita',
      'United Arab Emirates': 'Emirati Arabi Uniti',
      'UAE': 'Emirati Arabi Uniti',
      'Qatar': 'Qatar',
      'China': 'Cina',
      'India': 'India',
      'South Africa': 'Sudafrica',
      'Colombia': 'Colombia',
      'Chile': 'Cile',
      'Peru': 'Perù',
      'Ecuador': 'Ecuador',
      'Uruguay': 'Uruguay',
      'Paraguay': 'Paraguay',
      'Bolivia': 'Bolivia',
      'Costa Rica': 'Costa Rica',
      'USA': 'USA',
      'United States': 'USA',
      'United States of America': 'USA',
      'Europe': 'Europa',
      'World': 'Internazionale',
      'International': 'Internazionale',
    };

    return aliases[country] ?? country;
  }

  // ============================================================
  // CONVERSIONE API -> MATCH MODEL
  // ============================================================

  List<MatchModel> _convertResponseToMatches(List<dynamic> response) {
    final matches = <MatchModel>[];

    for (final match in response) {
      final leagueData = match["league"] ?? {};

      final int leagueId = leagueData["id"] ?? 0;

      final String leagueName = leagueData["name"] ?? "";

      final String apiCountry = leagueData["country"] ?? "";

      // ========================================================
      // CERCHIAMO LA COMPETIZIONE NEL LEAGUE MANAGER
      // ========================================================

      final leagueInfo = LeagueManager.findById(leagueId);

      // ========================================================
      // VALORI DI DEFAULT
      // ========================================================

      String country = _normalizeCountry(apiCountry);

      String countryCode = "";

      String leagueType = "domestic";

      bool isEuropeanCup = false;

      bool isFriendly = false;

      bool isNational = false;

      double aiWeight = 0.70;

      // ========================================================
      // COMPETIZIONE CONOSCIUTA
      // ========================================================

      if (leagueInfo != null) {
        country = _normalizeCountry(leagueInfo.country);

        countryCode = leagueInfo.countryCode;

        leagueType = leagueInfo.type.name;

        isEuropeanCup = leagueInfo.isEuropeanCup;

        isFriendly = leagueInfo.isFriendly;

        isNational = leagueInfo.isNationalCompetition;

        aiWeight = leagueInfo.aiWeight;
      } else {
        // ======================================================
        // CLASSIFICAZIONE AUTOMATICA
        // ======================================================

        final name = leagueName.toLowerCase();

        final countryLower = apiCountry.toLowerCase();

        // ------------------------------------------------------
        // AMICHEVOLI
        // ------------------------------------------------------

        if (name.contains("friendly") ||
            name.contains("friendlies") ||
            name.contains("amical")) {
          isFriendly = true;

          leagueType = "friendly";

          aiWeight = 0.60;
        }

        // ------------------------------------------------------
        // NAZIONALI
        // ------------------------------------------------------

        if (name.contains("world cup") ||
            name.contains("euro") ||
            name.contains("nations league") ||
            name.contains("africa cup") ||
            name.contains("copa america") ||
            name.contains("asian cup")) {
          isNational = true;

          leagueType = "national";

          aiWeight = 0.85;
        }

        // ------------------------------------------------------
        // COPPE EUROPEE
        // ------------------------------------------------------

        if (countryLower == "europe" ||
            name.contains("champions league") ||
            name.contains("europa league") ||
            name.contains("conference league")) {
          isEuropeanCup = true;

          leagueType = "europeanCup";

          aiWeight = 0.90;

          country = "Europa";

          countryCode = "EU";
        }

        // ------------------------------------------------------
        // COPPE NAZIONALI
        // ------------------------------------------------------

        if (!isEuropeanCup &&
            !isFriendly &&
            !isNational &&
            (name.contains("cup") ||
                name.contains("copa") ||
                name.contains("coppa") ||
                name.contains("coupe") ||
                name.contains("pokal"))) {
          leagueType = "domesticCup";

          aiWeight = 0.65;
        }

        // ------------------------------------------------------
        // FEMMINILI
        // ------------------------------------------------------

        if (name.contains("women") ||
            name.contains("woman") ||
            name.contains("feminine") ||
            name.contains("femminile") ||
            name.contains("ladies") ||
            name.contains("w league")) {
          leagueType = "women";
        }

        // ------------------------------------------------------
        // GIOVANILI
        // ------------------------------------------------------

        if (name.contains("u17") ||
            name.contains("u18") ||
            name.contains("u19") ||
            name.contains("u20") ||
            name.contains("u21") ||
            name.contains("u23") ||
            name.contains("youth") ||
            name.contains("primavera")) {
          leagueType = "youth";
        }
      }

      // ========================================================
      // NORMALIZZAZIONE FINALE
      // ========================================================

      country = _normalizeCountry(country);

      // ========================================================
      // CREA MATCH
      // ========================================================

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

    // ==========================================================
    // LOG
    // ==========================================================

    print('');
    print('========================================');
    print('SMARTBET - PARTITE DISPONIBILI');
    print('========================================');
    print('API ricevute: ${response.length}');
    print('Partite caricate: ${matches.length}');
    print('========================================');

    return matches;
  }
}
