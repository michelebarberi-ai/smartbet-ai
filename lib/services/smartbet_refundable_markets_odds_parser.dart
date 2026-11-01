/// P19H: accetta soltanto quote esplicite FULL-TIME del bookmaker.
/// Non confonde mercati primo/secondo tempo con quelli a tempo pieno.
class SmartBetRefundableMarketsOddsParser {
  const SmartBetRefundableMarketsOddsParser._();

  static String? outcomeFor({required String betName, required String value}) {
    final bet = betName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final raw = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    if (bet == 'draw no bet' || bet == 'draw no bet full time') {
      if (raw == 'home' || raw == '1') return 'DNB CASA';
      if (raw == 'away' || raw == '2') return 'DNB OSPITE';
      return null;
    }

    // Le linee con .5 non consentono rimborso/mezza vincita:
    // il ranking per probabilità resta quindi binario e confrontabile.
    // Le linee intere o al quarto sono già liquidabili nello storico,
    // ma richiedono una UX distinta e NON vengono messe in schedina.
    if (bet != 'asian handicap' && bet != 'asian handicap full time') {
      return null;
    }
    final match = RegExp(r'^(home|away)\s+([+-]?[012]\.5)$').firstMatch(raw);
    if (match == null) return null;
    final side = match.group(1) == 'home' ? 'CASA' : 'OSPITE';
    final line = double.tryParse(match.group(2)!);
    if (line == null || !line.isFinite) return null;
    final formatted = line == 0 ? '0' : line.toStringAsFixed(1);
    return 'HCP ASIA $side $formatted';
  }
}
