import '../models/match_model.dart';

class ItalyScheduleFilter {
  const ItalyScheduleFilter._();

  static bool allows(MatchModel match) {
    final country = _normalize(match.country);
    final league = _normalize(match.league);

    if (league.isEmpty) return false;

    // Competizioni che normalmente vogliamo evitare
    const blocked = [
      'u17',
      'u18',
      'u19',
      'u20',
      'u21',
      'u23',
      'youth',
      'primavera',
      'reserve',
      'reserves',
      'friendly',
      'friendlies',
      'amichevole',
    ];

    if (blocked.any(league.contains)) {
      return false;
    }

    // Alcune competizioni giovanili non riportano "U21" nel nome del
    // campionato. "Premier League Cup" non e' la Premier League senior
    // (nel 2026/27 e' una coppa delle accademie U21), e non deve passare
    // soltanto per la sottostringa "premier league".
    const youthCompetitions = [
      'premier league cup',
      'premier league international cup',
      'premier league 2',
      'professional development league',
      'fa youth cup',
    ];
    if (youthCompetitions.any((name) => league == name ||
        league.startsWith('$name -') ||
        league.startsWith('$name group'))) {
      return false;
    }

    // I nomi delle squadre possono essere gli unici a indicare U21/U23.
    // Non escludere le nazionali senior o club senior per corrispondenze
    // accidentali di parole; solo i marcatori espliciti di categoria.
    final teams = '${_normalize(match.homeTeam)} | ${_normalize(match.awayTeam)}';
    if (RegExp(r'\bu(?:17|18|19|20|21|23)\b|\bunder[ -]?(?:17|18|19|20|21|23)\b')
        .hasMatch(teams)) {
      return false;
    }

    // Coppe / competizioni internazionali principali
    const international = [
      'champions league',
      'europa league',
      'conference league',
      'nations league',
      'world cup',
      'club world cup',
      'european championship',
      'copa libertadores',
      'copa sudamericana',
    ];

    if (international.any(league.contains)) {
      return true;
    }

    if (_countryIs(country, ['italia', 'italy'])) {
      return _leagueIs(league, [
        'serie a',
        'serie b',
        'serie c',
        // La Serie D e' una competizione senior e non va scartata
        // quando il provider include i suoi gironi nel calendario.
        'serie d',
        'coppa italia',
        'supercoppa',
      ]);
    }

    if (_countryIs(country, ['inghilterra', 'england'])) {
      return _leagueIs(league, [
        'premier league',
        'championship',
        'fa cup',
        'efl cup',
        'league cup',
      ]);
    }

    if (_countryIs(country, ['spagna', 'spain'])) {
      return _leagueIs(league, [
        'la liga',
        'laliga',
        'segunda division',
        'copa del rey',
        'supercopa',
      ]);
    }

    if (_countryIs(country, ['germania', 'germany'])) {
      return _leagueIs(league, [
        'bundesliga',
        '2. bundesliga',
        'dfb pokal',
        'dfb-pokal',
      ]);
    }

    if (_countryIs(country, ['francia', 'france'])) {
      return _leagueIs(league, ['ligue 1', 'ligue 2', 'coupe de france']);
    }

    if (_countryIs(country, ['portogallo', 'portugal'])) {
      return _leagueIs(league, [
        'primeira liga',
        'liga portugal',
        'taca de portugal',
      ]);
    }

    if (_countryIs(country, ['olanda', 'netherlands'])) {
      return _leagueIs(league, ['eredivisie', 'eerste divisie', 'knvb beker']);
    }

    if (_countryIs(country, ['belgio', 'belgium'])) {
      return _leagueIs(league, [
        'jupiler pro league',
        'first division a',
        'challenger pro league',
      ]);
    }

    if (_countryIs(country, ['scozia', 'scotland'])) {
      return _leagueIs(league, ['premiership', 'championship', 'scottish cup']);
    }

    if (_countryIs(country, ['turchia', 'turkey'])) {
      return _leagueIs(league, ['super lig', 'super league']);
    }

    if (_countryIs(country, ['grecia', 'greece'])) {
      return _leagueIs(league, ['super league']);
    }

    if (_countryIs(country, ['austria'])) {
      return _leagueIs(league, ['bundesliga']);
    }

    if (_countryIs(country, ['svizzera', 'switzerland'])) {
      return _leagueIs(league, ['super league']);
    }

    if (_countryIs(country, ['danimarca', 'denmark'])) {
      return _leagueIs(league, ['superliga']);
    }

    if (_countryIs(country, ['svezia', 'sweden'])) {
      return _leagueIs(league, ['allsvenskan']);
    }

    if (_countryIs(country, ['norvegia', 'norway'])) {
      return _leagueIs(league, ['eliteserien']);
    }

    if (_countryIs(country, ['usa', 'united states', 'stati uniti'])) {
      return _leagueIs(league, ['major league soccer', 'mls']);
    }

    if (_countryIs(country, ['brasile', 'brazil'])) {
      return _leagueIs(league, ['serie a', 'serie b', 'copa do brasil']);
    }

    if (_countryIs(country, ['argentina'])) {
      return _leagueIs(league, [
        'liga profesional',
        'primera division',
        'copa argentina',
      ]);
    }

    if (_countryIs(country, ['messico', 'mexico'])) {
      return _leagueIs(league, ['liga mx']);
    }

    if (_countryIs(country, ['arabia saudita', 'saudi arabia'])) {
      return _leagueIs(league, ['pro league']);
    }

    if (_countryIs(country, ['giappone', 'japan'])) {
      return _leagueIs(league, ['j1 league']);
    }

    if (_countryIs(country, ['corea del sud', 'south korea'])) {
      return _leagueIs(league, ['k league 1']);
    }

    if (_countryIs(country, ['australia'])) {
      return _leagueIs(league, ['a-league', 'a league']);
    }

    return false;
  }

  static bool _countryIs(String country, List<String> values) {
    return values.any((value) => country == _normalize(value));
  }

  static bool _leagueIs(String league, List<String> values) {
    return values.any((value) {
      final name = _normalize(value);
      // Avoid admitting unrelated competitions through partial names
      // (for example 'Serie Amateur' matching 'Serie A').
      return league == name ||
          league.startsWith('$name - ') ||
          league.startsWith('$name group ') ||
          league.startsWith('$name girone ');
    });
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('à', 'a')
        .replaceAll('á', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('í', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ó', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
