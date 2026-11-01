/// Riconosce esclusivamente quote per mercati completi ed espliciti.
/// Non deriva quote da altri mercati e non confonde 1T/2T con full-time.
class SmartBetExtraMarketsOddsParser {
  const SmartBetExtraMarketsOddsParser._();

  static const _multigol = <String>{
    'MULTIGOL 1-4',
    'MULTIGOL 2-4',
    'MULTIGOL 2-5',
    'MULTIGOL 3-5',
  };
  static const _combos = <String>{
    '1X + O1.5',
    'X2 + O1.5',
    '1X + U3.5',
    'X2 + U3.5',
    '1 + O1.5',
    '2 + O1.5',
    '1 + U3.5',
    '2 + U3.5',
    '1X + O2.5',
    'X2 + O2.5',
    '1X + U2.5',
    'X2 + U2.5',
  };

  static String? outcomeFor({required String betName, required String value}) {
    final bet = betName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[ _]+'), ' ')
        .replaceAll('multi-goals', 'multi goals');
    final raw = value.trim();

    final isMultigol =
        bet == 'multigol' ||
        bet == 'multi goals' ||
        bet == 'multigoals' ||
        bet == 'total goals range' ||
        bet == 'goals range' ||
        bet.startsWith('multi goals ') ||
        bet.startsWith('multigoals ');

    if (isMultigol) {
      // Mercato multigol con fascia nel value, oppure fascia nel nome
      // quando il value e' un Yes esplicito.
      var source = raw;
      if (raw.toLowerCase() == 'yes') {
        source = bet.replaceFirst(
          RegExp(r'^(?:multi goals|multigoals)\s+'),
          '',
        );
      }
      final match = RegExp(
        r'^(?:multigol\s*)?([0-9]+)\s*[-–]\s*([0-9]+)$',
        caseSensitive: false,
      ).firstMatch(source);
      if (match == null) return null;
      final key = 'MULTIGOL ${match.group(1)}-${match.group(2)}';
      return _multigol.contains(key) ? key : null;
    }

    // Combinazioni solo se il mercato del provider identifica
    // esplicitamente un risultato + totale gol FULL TIME.
    const names = <String>{
      'double chance and total goals',
      'double chance and over under',
      'match result and total goals',
      'match result and over under',
      'match winner and total goals',
    };
    if (!names.contains(bet)) return null;

    final normalized = raw
        .toLowerCase()
        .replaceAll('home', '1')
        .replaceAll('away', '2')
        .replaceAll('over', 'o')
        .replaceAll('under', 'u')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final match = RegExp(
      r'^(1x|x2|1|2)\s*(?:&|\+|and)\s*([ou])\s*(1\.5|2\.5|3\.5)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return null;
    final key =
        '${match.group(1)!.toUpperCase()} + '
        '${match.group(2)!.toUpperCase()}${match.group(3)}';
    return _combos.contains(key) ? key : null;
  }
}
