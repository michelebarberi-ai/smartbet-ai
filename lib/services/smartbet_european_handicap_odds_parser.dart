/// Normalizza esclusivamente Handicap europeo full-time
/// API-Football ID 9. Non tratta Handicap asiatici
/// né Handicap dei tempi, corner o cartellini.
class SmartBetEuropeanHandicapOddsParser {
  const SmartBetEuropeanHandicapOddsParser._();

  static String? outcomeFor({required int betId, required String value}) {
    if (betId != 9) return null;

    final match = RegExp(
      r'^(Home|Draw|Away)\s*([+-]?[0-9]+)$',
      caseSensitive: false,
    ).firstMatch(value.trim());

    if (match == null) return null;

    final line = int.tryParse(match.group(2)!);

    if (line == null || line < -5 || line > 5) {
      return null;
    }

    final selection = switch (match.group(1)!.toLowerCase()) {
      'home' => '1',
      'draw' => 'X',
      'away' => '2',
      _ => '',
    };

    if (selection.isEmpty) return null;

    return 'HCP EURO CASA $line $selection';
  }
}
