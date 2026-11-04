/// P22: solo presentazione. NON modifica scelta, probabilita o quote.
/// Ordine editoriale ispirato ai palinsesti italiani, non una copia di Sisal.
class GoalVdLineCompetitionOrder {
  const GoalVdLineCompetitionOrder._();

  static const _preferred = <String>[
    'EUROPA',
    'MONDO',
    'ITALIA',
    'SPECIALI',
    'INGHILTERRA',
    'SPAGNA',
    'FRANCIA',
    'GERMANIA',
    'OLANDA',
    'BELGIO',
    'PORTOGALLO',
    'AMERICA',
    'ASIA',
  ];

  static const _aliases = <String, String>{
    'europe': 'EUROPA',
    'europa': 'EUROPA',
    'world': 'MONDO',
    'mondo': 'MONDO',
    'international': 'MONDO',
    'italy': 'ITALIA',
    'italia': 'ITALIA',
    'special': 'SPECIALI',
    'speciali': 'SPECIALI',
    'england': 'INGHILTERRA',
    'inghilterra': 'INGHILTERRA',
    'spain': 'SPAGNA',
    'spagna': 'SPAGNA',
    'france': 'FRANCIA',
    'francia': 'FRANCIA',
    'germany': 'GERMANIA',
    'germania': 'GERMANIA',
    'netherlands': 'OLANDA',
    'holland': 'OLANDA',
    'paesi bassi': 'OLANDA',
    'olanda': 'OLANDA',
    'belgium': 'BELGIO',
    'belgio': 'BELGIO',
    'portugal': 'PORTOGALLO',
    'portogallo': 'PORTOGALLO',
    'america': 'AMERICA',
    'americas': 'AMERICA',
    'asia': 'ASIA',
    'united states': 'USA',
    'united states of america': 'USA',
    'stati uniti': 'USA',
    'usa': 'USA',
    'scotland': 'SCOZIA',
    'scozia': 'SCOZIA',
    'northern ireland': 'IRLANDA DEL NORD',
    'irlanda del nord': 'IRLANDA DEL NORD',
    'wales': 'GALLES',
    'galles': 'GALLES',
    'turkey': 'TURCHIA',
    'turkiye': 'TURCHIA',
    'turchia': 'TURCHIA',
    'brazil': 'BRASILE',
    'brasile': 'BRASILE',
    'switzerland': 'SVIZZERA',
    'svizzera': 'SVIZZERA',
    'sweden': 'SVEZIA',
    'svezia': 'SVEZIA',
    'norway': 'NORVEGIA',
    'norvegia': 'NORVEGIA',
    'denmark': 'DANIMARCA',
    'danimarca': 'DANIMARCA',
    'poland': 'POLONIA',
    'polonia': 'POLONIA',
    'austria': 'AUSTRIA',
    'greece': 'GRECIA',
    'grecia': 'GRECIA',
    'czech republic': 'REPUBBLICA CECA',
    'czech-republic': 'REPUBBLICA CECA',
    'repubblica ceca': 'REPUBBLICA CECA',
    'ireland': 'IRLANDA',
    'irlanda': 'IRLANDA',
    'croatia': 'CROAZIA',
    'croazia': 'CROAZIA',
    'serbia': 'SERBIA',
    'ukraine': 'UCRAINA',
    'ucraina': 'UCRAINA',
    'mexico': 'MESSICO',
    'messico': 'MESSICO',
    'peru': 'PERU',
    'japan': 'GIAPPONE',
    'giappone': 'GIAPPONE',
    'south korea': 'COREA DEL SUD',
    'corea del sud': 'COREA DEL SUD',
    'saudi arabia': 'ARABIA SAUDITA',
    'arabia saudita': 'ARABIA SAUDITA',
    'united arab emirates': 'EMIRATI ARABI',
    'emirati arabi': 'EMIRATI ARABI',
    'unknown': 'ALTRI',
    'altri': 'ALTRI',
  };

  static String _normalize(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll('à', 'a')
      .replaceAll('á', 'a')
      .replaceAll('â', 'a')
      .replaceAll('è', 'e')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ì', 'i')
      .replaceAll('í', 'i')
      .replaceAll('ò', 'o')
      .replaceAll('ó', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u');

  static String country(String raw) {
    if (raw.trim().isEmpty) return 'ALTRI';
    final key = _normalize(raw);
    return _aliases[key] ?? raw.trim().toUpperCase();
  }

  static String league(String raw) =>
      raw.trim().isEmpty ? 'ALTRA COMPETIZIONE' : raw.trim();

  static int compareCountries(String a, String b) {
    final first = country(a);
    final second = country(b);
    final firstRank = _preferred.indexOf(first);
    final secondRank = _preferred.indexOf(second);
    if (firstRank >= 0 && secondRank >= 0) {
      return firstRank.compareTo(secondRank);
    }
    if (firstRank >= 0) return -1;
    if (secondRank >= 0) return 1;
    if (first == 'ALTRI') return second == 'ALTRI' ? 0 : 1;
    if (second == 'ALTRI') return -1;
    return first.toLowerCase().compareTo(second.toLowerCase());
  }

  static int compareLeagues(String a, String b) {
    // Non altera la classifica dei pronostici: ordina le sole intestazioni.
    final la = league(a).toLowerCase();
    final lb = league(b).toLowerCase();
    return la.compareTo(lb);
  }

  static int compareTimes(String? a, String? b) {
    final first = DateTime.tryParse(a ?? '');
    final second = DateTime.tryParse(b ?? '');
    if (first != null && second != null) return first.compareTo(second);
    if (first != null) return -1;
    if (second != null) return 1;
    return 0; // In Live, dove manca l'orario, conserva l'ordine del feed.
  }

  static String flag(String value) {
    switch (country(value)) {
      case 'EUROPA':
        return '🌍';
      case 'MONDO':
        return '🌐';
      case 'ITALIA':
        return '🇮🇹';
      case 'INGHILTERRA':
        return '🏴';
      case 'SPAGNA':
        return '🇪🇸';
      case 'FRANCIA':
        return '🇫🇷';
      case 'GERMANIA':
        return '🇩🇪';
      case 'OLANDA':
        return '🇳🇱';
      case 'BELGIO':
        return '🇧🇪';
      case 'PORTOGALLO':
        return '🇵🇹';
      case 'AMERICA':
        return '🌎';
      case 'ASIA':
        return '🌏';
      case 'USA':
        return '🇺🇸';
      case 'BRASILE':
        return '🇧🇷';
      case 'SCOZIA':
        return '🏴';
      case 'GALLES':
        return '🏴';
      case 'TURCHIA':
        return '🇹🇷';
      case 'GIAPPONE':
        return '🇯🇵';
      case 'COREA DEL SUD':
        return '🇰🇷';
      case 'ARABIA SAUDITA':
        return '🇸🇦';
      case 'SVIZZERA':
        return '🇨🇭';
      case 'SVEZIA':
        return '🇸🇪';
      case 'NORVEGIA':
        return '🇳🇴';
      case 'DANIMARCA':
        return '🇩🇰';
      case 'GRECIA':
        return '🇬🇷';
      case 'POLONIA':
        return '🇵🇱';
      case 'AUSTRIA':
        return '🇦🇹';
      case 'CROAZIA':
        return '🇭🇷';
      case 'UCRAINA':
        return '🇺🇦';
      case 'REPUBBLICA CECA':
        return '🇨🇿';
      case 'MESSICO':
        return '🇲🇽';
      case 'IRLANDA':
        return '🇮🇪';
      case 'IRLANDA DEL NORD':
        return '🇬🇧';
      case 'EMIRATI ARABI':
        return '🇦🇪';
      case 'ARGENTINA':
        return '🇦🇷';
      case 'ALGERIA':
        return '🇩🇿';
      case 'AUSTRALIA':
        return '🇦🇺';
      case 'BOLIVIA':
        return '🇧🇴';
      case 'BOTSWANA':
        return '🇧🇼';
      case 'BULGARIA':
        return '🇧🇬';
      case 'CAMERUN':
        return '🇨🇲';
      case 'CANADA':
        return '🇨🇦';
      case 'CILE':
        return '🇨🇱';
      case 'CINA':
        return '🇨🇳';
      case 'CIPRO':
        return '🇨🇾';
      case 'COLOMBIA':
        return '🇨🇴';
      case 'COSTA RICA':
        return '🇨🇷';
      case 'ECUADOR':
        return '🇪🇨';
      case 'EGITTO':
        return '🇪🇬';
      case 'EL SALVADOR':
        return '🇸🇻';
      case 'ESTONIA':
        return '🇪🇪';
      case 'FILIPPINE':
        return '🇵🇭';
      case 'FINLANDIA':
        return '🇫🇮';
      case 'GIORDANIA':
        return '🇯🇴';
      case 'GUATEMALA':
        return '🇬🇹';
      case 'HONDURAS':
        return '🇭🇳';
      case 'INDIA':
        return '🇮🇳';
      case 'INDONESIA':
        return '🇮🇩';
      case 'ISRAELE':
        return '🇮🇱';
      case 'KOSOVO':
        return '🇽🇰';
      case 'LETTONIA':
        return '🇱🇻';
      case 'LITUANIA':
        return '🇱🇹';
      case 'MAROCCO':
        return '🇲🇦';
      case 'MONTENEGRO':
        return '🇲🇪';
      case 'NIGERIA':
        return '🇳🇬';
      case 'OMAN':
        return '🇴🇲';
      case 'PARAGUAY':
        return '🇵🇾';
      case 'PERU':
        return '🇵🇪';
      case 'QATAR':
        return '🇶🇦';
      case 'SLOVACCHIA':
        return '🇸🇰';
      case 'SLOVENIA':
        return '🇸🇮';
      case 'SUDAFRICA':
        return '🇿🇦';
      case 'UGANDA':
        return '🇺🇬';
      case 'UNGHERIA':
        return '🇭🇺';
      case 'URUGUAY':
        return '🇺🇾';
      case 'VENEZUELA':
        return '🇻🇪';
      case 'ZAMBIA':
        return '🇿🇲';
      default:
        return '🌍';
    }
  }
}
