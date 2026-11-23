import 'goalvdline_extra_markets_service.dart';

/// Strict B78 parser for bookmaker-supplied prices of NEW market families.
///
/// It never infers a price from a full-time line, a player prop, a team prop,
/// or a Bet Builder. When bookmaker market naming is ambiguous return null.
class GoalVdLineExtraMarketsOddsParser {
  const GoalVdLineExtraMarketsOddsParser._();

  static String? outcomeFor({
    required String betName,
    required String value,
  }) {
    final bet = betName.trim().toLowerCase()
        .replaceAll(RegExp(r'[_\s]+'), ' ')
        .replaceAll('-', ' ');
    final label = value.trim().toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (bet.isEmpty || label.isEmpty) return null;

    const firstHalf = <String>{
      'first half winner',
      '1st half winner',
      'first half result',
      '1st half result',
      '1st half 1x2',
      'first half 1x2',
      '1st half match winner',
    };
    const secondHalf = <String>{
      'second half winner',
      '2nd half winner',
      'second half result',
      '2nd half result',
      '2nd half 1x2',
      'second half 1x2',
      '2nd half match winner',
    };
    if (firstHalf.contains(bet) || secondHalf.contains(bet)) {
      final outcome = switch (label) {
        'home' || '1' => '1',
        'draw' || 'x' => 'X',
        'away' || '2' => '2',
        _ => null,
      };
      return outcome == null
          ? null : '${firstHalf.contains(bet) ? "1T" : "2T"} $outcome';
    }

    const corners = <String>{
      'total corners',
      'total corners over under',
      'corners over under',
      'match corners',
      'corners total',
    };
    const shots = <String>{
      'total shots on goal',
      'total shots on target',
      'shots on target over under',
      'match shots on target',
    };

    final family = corners.contains(bet)
        ? GoalVdLineExtraMarketFamily.totalCorners
        : shots.contains(bet)
            ? GoalVdLineExtraMarketFamily.totalShotsOnTarget
            : null;
    if (family == null) return null;
    final normalized = label.replaceAll(',', '.');
    final match = RegExp(
      r'^(over|under)\s+(\d+\.5)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return null;
    final market = '${family == GoalVdLineExtraMarketFamily.totalCorners ? "CORNER" : "TIRI PORTA"} '
        '${match.group(1)!.toUpperCase()} ${match.group(2)}';
    return GoalVdLineExtraMarketsService.marketFamilies[family]!
            .contains(market)
        ? market
        : null;
  }
}
